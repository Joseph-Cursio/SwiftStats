//
//  MutationResultsReader.swift
//  SwiftStatsCore
//
//  The state of reading a results file, line by line (M6, design §2):
//  the readable sessions, each key's winning `mutant` line, the control
//  runs, a `stopped` line and the lines skipped. `MutationResultsFile`
//  feeds it and asks it for the results.
//

import Foundation

/// A results file read so far.
struct MutationResultsReader {
    /// One readable session.
    private struct Session {
        /// Its header.
        let header: MutationResultsFile.HeaderLine
        /// Its tree, rebuilt through `projectDelta`; empty when it records
        /// none.
        let tree: [String: String]
        /// Its tree's hash; nil when it records no tree.
        let treeSHA256: String?
        /// Its end line.
        var end: MutationResultsFile.EndLine?
    }

    /// The numbers of the lines skipped.
    var skipped: [Int] = []
    /// The `stopped` line, if any.
    private(set) var stopped: MutationStop?
    /// The readable sessions, in file order.
    private var sessions: [Session] = []
    /// Each key's winning line.
    private var latest: [MutantKey: MutationResultsFile.MutantLine] = [:]
    /// How many control runs.
    private var controlRuns = 0
    /// How many control runs failed, crashed or timed out.
    private var controlFailures = 0
    /// The decoder.
    private let decoder = JSONDecoder()

    /// Adds `line`'s record, or returns false when it doesn't read or its
    /// session has no readable header. A header in a newer format refuses
    /// the file.
    mutating func add(_ line: Data) throws(MutationFailure) -> Bool {
        guard let kind = try? decoder.decode(MutationResultsFile.KindLine.self, from: line).kind else {
            return false
        }
        switch kind {
        case "header":
            return try addHeader(line)

        case "mutant":
            return addMutant(line)

        case "retired":
            return addRetired(line)

        case "control":
            return addControl(line)

        case "stopped":
            return addStopped(line)

        case "end":
            return addEnd(line)

        default:
            // `propertyRerun` (SwiftStats configures no property tests),
            // and kinds a later SwiftMutator writes.
            return true
        }
    }

    /// The results read, from a file whose SHA-256 is `sha256`; nil when
    /// no header read.
    func results(sha256: String) -> MutationResults? {
        guard let last = sessions.last, let facts = MutationResultsFile.facts(of: sessions.map(\.header)) else {
            return nil
        }
        var mutants = latest.values.map(MutationResultsFile.mutant(of:))
        var listed = Set(latest.keys)
        for entry in last.header.notCovered where listed.insert(entry.key).inserted {
            mutants.append(MutationResultsFile.notCovered(entry, tree: last.tree))
        }
        return MutationResults(
            mutants: mutants.sorted { $0.key < $1.key },
            facts: facts,
            sessions: sessions.count,
            formatVersions: Set(sessions.map(\.header.formatVersion)).sorted(),
            tree: last.tree,
            listsNotCovered: last.header.listsNotCovered || last.header.skipCoverage,
            controlRuns: controlRuns,
            controlFailures: controlFailures,
            end: last.end.map { MutationResults.End(reason: $0.reason, detail: $0.detail, endedAt: $0.endedAt) },
            tested: latest.count,
            skippedLines: skipped,
            sha256: sha256
        )
    }

    /// Adds the header `line`, or returns false when it doesn't read, or
    /// its `projectDelta` doesn't rebuild from an earlier session's tree
    /// into the tree it names.
    private mutating func addHeader(_ line: Data) throws(MutationFailure) -> Bool {
        if let version = try? decoder.decode(MutationResultsFile.VersionLine.self, from: line).formatVersion,
           version > MutationResultsFile.newestFormatVersion {
            throw MutationFailure(description: MutationResultsFile.newerFormatReason(version))
        }
        guard let header = try? decoder.decode(MutationResultsFile.HeaderLine.self, from: line) else {
            return false
        }
        guard let delta = header.projectDelta else {
            sessions.append(Session(
                header: header,
                tree: header.project?.files ?? [:],
                treeSHA256: header.project?.treeSHA256
            ))
            return true
        }
        guard let base = sessions.last(where: { $0.treeSHA256 == delta.baseTreeSHA256 }) else {
            return false
        }
        let tree = MutationTree.applying(files: delta.files, removed: delta.removed, to: base.tree)
        guard MutationTree.hash(of: tree) == delta.treeSHA256 else {
            return false
        }
        sessions.append(Session(header: header, tree: tree, treeSHA256: delta.treeSHA256))
        return true
    }

    /// Adds the `mutant` line `line`, or returns false when it doesn't
    /// read, records an outcome or an ending no SwiftMutator writes, or
    /// its session has no readable header.
    private mutating func addMutant(_ line: Data) -> Bool {
        guard let record = try? decoder.decode(MutationResultsFile.MutantLine.self, from: line),
              MutationVerdict.outcomes.contains(record.outcome),
              MutationResultsFile.endings.contains(record.endedBy),
              sessionIndex(record.session) != nil
        else {
            return false
        }
        latest[record.key] = record
        return true
    }

    /// Drops the earlier lines of the keys the `retired` line `line`
    /// names, or returns false when it doesn't read or its session has no
    /// readable header.
    private mutating func addRetired(_ line: Data) -> Bool {
        guard let retired = try? decoder.decode(MutationResultsFile.RetiredLine.self, from: line),
              sessionIndex(retired.session) != nil
        else {
            return false
        }
        for key in retired.keys {
            latest.removeValue(forKey: key.key)
        }
        return true
    }

    /// Counts the `control` line `line`, or returns false when it doesn't
    /// read or its session has no readable header.
    private mutating func addControl(_ line: Data) -> Bool {
        guard let control = try? decoder.decode(MutationResultsFile.ControlLine.self, from: line),
              sessionIndex(control.session) != nil
        else {
            return false
        }
        controlRuns += 1
        if control.outcome != "passed" {
            controlFailures += 1
        }
        return true
    }

    /// Keeps the `stopped` line `line`, or returns false when it doesn't
    /// read.
    private mutating func addStopped(_ line: Data) -> Bool {
        guard let record = try? decoder.decode(MutationResultsFile.StoppedLine.self, from: line) else {
            return false
        }
        stopped = MutationStop(
            step: record.step,
            reason: record.reason,
            detail: record.detail,
            failedTests: record.failedTests,
            failedTestCount: record.failedTestCount
        )
        return true
    }

    /// Ends the session of the `end` line `line`, or returns false when it
    /// doesn't read, gives a reason no SwiftMutator writes, or its session
    /// has no readable header.
    private mutating func addEnd(_ line: Data) -> Bool {
        guard let end = try? decoder.decode(MutationResultsFile.EndLine.self, from: line),
              MutationResultsFile.endReasons.contains(end.reason),
              let index = sessionIndex(end.session)
        else {
            return false
        }
        sessions[index].end = end
        return true
    }

    /// The latest readable session numbered `number`.
    private func sessionIndex(_ number: Int) -> Int? {
        sessions.lastIndex { $0.header.session == number }
    }
}
