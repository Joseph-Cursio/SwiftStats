//
//  MutationMerge.swift
//  SwiftStatsCore
//
//  A `--since` run merged with its base snapshot's results (M6, design
//  §6.1), path by path. The base's tree is its files; the new tree is the
//  run's last header's, or, when it wrote no results file, SwiftStats' own
//  hash of each Swift file of the copy. A path exists when the new tree
//  holds it (never a look on disk, so a case-only rename on a
//  case-insensitive volume can't keep its old spelling), compared in NFC.
//  A production path SwiftMutator chose, or one the run has a mutant in,
//  is retested: its rows are the run's, the base's dropped, every function
//  of it fresh. A run that wrote no results file tested nothing, so a
//  production path its selection holds is unlisted: its rows are dropped
//  and its code no test ran isn't listed. Any other path whose hash is the
//  base's keeps the base's rows, carried, placed again on this scan's
//  records and pointing at a copy of the run that tested them, which
//  names the base it came from (a path the base held unlisted stays so).
//  A path of the base the new tree lacks is deleted. A production path
//  whose hash changed, or the base lacks, that wasn't retested or
//  unlisted (an ignored file edited, a nested repository's), one with a
//  base row of no file hash, and an unchanged one the base held untested
//  (moved into a production target since), is unresolved: no results, and
//  the merged results are incomplete. Test paths the selection holds are marked:
//  carried verdicts weren't retested against them.
//

import Foundation

/// A `--since` run's results merged with its base's.
struct MutationMerge {
    /// The merged results, and the notes their collector's reason adds.
    struct Merged {
        /// The merged results, as the store's rows hold them.
        let report: MutationReport
        /// What the merge did, as reason notes.
        let notes: [String]
    }

    /// What became of a path.
    private enum Outcome {
        /// Retested by the run.
        case retested
        /// Changed, but the run wrote no results file.
        case unlisted
        /// Unchanged: the base's rows kept.
        case carried
        /// In the base's tree, gone from the new one.
        case deleted
        /// Changed, neither retested nor unlisted: no results.
        case unresolved
        /// Changed, but not a production path: none of its rows kept.
        case untested
    }

    /// What a Swift file's name ends with.
    private static let swiftSuffix = ".swift"

    /// The base.
    let base: MutationBase
    /// Places the mutants on this scan's records.
    let mapper: MutationMapper
    /// What the run's copy changed, and its tree when there is no header.
    let changes: MutationChanges

    /// `count` and `noun`, plural unless `count` is 1.
    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// `mutant`, placed as `placed`, as run `ordinal`'s carried row.
    private static func carried(_ mutant: Mutant, placed: MutationMapper.Placed, run ordinal: Int) -> Mutant {
        Mutant(
            path: mutant.path,
            line: mutant.line,
            column: mutant.column,
            occurrence: mutant.occurrence,
            operatorID: mutant.operatorID,
            anchor: placed.anchor,
            verdict: mutant.verdict,
            outcome: mutant.outcome,
            activated: mutant.activated,
            endedBy: mutant.endedBy,
            exitStatus: mutant.exitStatus,
            killedBy: mutant.killedBy,
            killedByComplete: mutant.killedByComplete,
            failedTestCount: mutant.failedTestCount,
            suspectOnly: mutant.suspectOnly,
            fileSHA256: mutant.fileSHA256,
            before: mutant.before,
            after: mutant.after,
            description: mutant.description,
            run: ordinal,
            session: mutant.session,
            durationSeconds: mutant.durationSeconds,
            carried: true,
            reused: mutant.reused,
            rerun: mutant.rerun,
            place: placed.place,
            owner: placed.owner,
            reason: placed.reason
        )
    }

    /// `results`, left by `run` (nil when the run wrote no results file),
    /// whose kills `suspects` judged, merged with the base.
    func merged(results: MutationResults?, run: MutationRunRecord?, suspects: SuspectReport) -> Merged {
        let paths = Paths(base: base, results: results, changes: changes)
        var outcomes: [String: Outcome] = [:]
        for path in paths.all {
            outcomes[path] = outcome(of: path, in: paths, ranWithResults: results != nil)
        }
        let carriedPaths = Set(outcomes.filter { $0.value == .carried }.keys)
        let keptRows = paths.baseRows.filter { carriedPaths.contains($0.key) || paths.isRowsOnly($0.key) }
        let referenced = Set(keptRows.values.joined().map(\.run)).union(
            carriedPaths.compactMap { paths.baseTree[$0]?.run }
        )
        let carriedRuns = base.report.runs.filter { referenced.contains($0.ordinal) }
        let renumbering = Dictionary(uniqueKeysWithValues: carriedRuns.enumerated().map { ($1.ordinal, $0) })
        let ordinal = carriedRuns.count
        var anchorings: [String: MutantAnchoring] = [:]
        let carriedRows = keptRows.keys.sorted().flatMap { path in
            (keptRows[path] ?? []).map { mutant in
                Self.carried(
                    mutant,
                    placed: mapper.place(
                        mutant.key,
                        fileSHA256: mutant.fileSHA256,
                        after: mutant.after,
                        anchorings: &anchorings
                    ),
                    run: renumbering[mutant.run, default: mutant.run]
                )
            }
        }
        let fresh = results.map { mapper.mutants(of: $0, run: ordinal, suspects: suspects) } ?? []
        let copies = carriedRuns.map { carried in
            carried.renumbered(renumbering[carried.ordinal, default: carried.ordinal], carriedFrom: base.source)
        }
        let runs = copies + [run?.renumbered(ordinal, carriedFrom: nil)].compactMap(\.self)
        let files = files(outcomes, paths: paths, renumbering: renumbering, ordinal: ordinal)
        let unresolved = files.count { $0.disposition == .unresolved }
        let report = MutationReport(
            collectedAt: run?.startedAt ?? base.report.collectedAt,
            complete: (results?.complete ?? true) && unresolved == 0,
            listsNotCovered: runs.isEmpty ? base.report.listsNotCovered : runs.allSatisfy(\.listsNotCovered),
            mode: .since,
            base: base.source,
            files: files,
            runs: runs,
            suspectTests: suspectTests(renumbering: renumbering)
                + (run == nil ? [] : MutationMapper.suspectTests(suspects, run: ordinal)),
            mutants: carriedRows + fresh
        )
        return Merged(report: MutationRows.normalized(report), notes: notes(files))
    }

    /// What becomes of the path whose NFC spelling is `path`, given
    /// `paths`, when the run wrote a results file (`ranWithResults`) or
    /// didn't.
    private func outcome(of path: String, in paths: Paths, ranWithResults: Bool) -> Outcome {
        guard let current = paths.newTree[path] else {
            return paths.baseTree[path] == nil ? .untested : .deleted
        }
        let isProduction = mapper.isProduction(current.path)
        if paths.freshPaths.contains(path) || (isProduction && paths.chosen.contains(path)) {
            return .retested
        }
        if ranWithResults == false, isProduction, paths.selection.contains(path) {
            return .unlisted
        }
        let rowsHaveHashes = (paths.baseRows[path] ?? []).allSatisfy { $0.fileSHA256 != nil }
        // A production path the base didn't test (a test target's file
        // then) has nothing to carry, however unchanged its bytes.
        if let earlier = paths.baseTree[path], earlier.sha256 == current.sha256, rowsHaveHashes,
           isProduction == false || earlier.disposition != .untested {
            return .carried
        }
        return isProduction ? .unresolved : .untested
    }

    /// The merged tree: each path of the new tree with what became of it
    /// (`outcomes`), and each deleted one, in `paths`; carried paths name
    /// their run as `renumbering` renumbers it, retested ones run
    /// `ordinal`.
    private func files(
        _ outcomes: [String: Outcome],
        paths: Paths,
        renumbering: [Int: Int],
        ordinal: Int
    ) -> [MutationFile] {
        outcomes.keys.sorted().compactMap { path -> MutationFile? in
            guard let outcome = outcomes[path] else {
                return nil
            }
            guard let current = paths.newTree[path] else {
                return paths.baseTree[path].map { earlier in
                    MutationFile(path: earlier.path, sha256: nil, disposition: .deleted, changedTest: false, run: nil)
                }
            }
            let changedTest = mapper.isTestFile(current.path) && paths.selection.contains(path)
            let (disposition, run) = disposition(of: path, spelled: current.path, outcome: outcome, paths: paths)
            return MutationFile(
                path: current.path,
                sha256: current.sha256,
                disposition: disposition,
                changedTest: changedTest,
                run: run.map { renumbering[$0, default: $0] } ?? (disposition == .tested ? ordinal : nil)
            )
        }
    }

    /// The disposition of the path whose NFC spelling is `path`, spelled
    /// `spelled` in the new tree, that became `outcome` in `paths`, and the
    /// run that tested it: the base's run, as the base numbers it, for a
    /// carried path, and nil otherwise (a retested one is the new run's,
    /// which the caller names).
    private func disposition(
        of path: String,
        spelled: String,
        outcome: Outcome,
        paths: Paths
    ) -> (MutationFileDisposition, Int?) {
        let isProduction = mapper.isProduction(spelled)
        switch outcome {
        case .retested:
            return (isProduction ? .tested : .untested, nil)

        case .carried:
            guard isProduction, let earlier = paths.baseTree[path] else {
                return (.untested, nil)
            }
            return earlier.disposition == .unlisted ? (.unlisted, nil) : (.carried, earlier.run)

        case .unlisted:
            return (.unlisted, nil)

        case .unresolved:
            return (.unresolved, nil)

        case .deleted, .untested:
            return (.untested, nil)
        }
    }

    /// The base's suspect tests of the runs carried, as `renumbering`
    /// renumbers them.
    private func suspectTests(renumbering: [Int: Int]) -> [MutationSuspectTest] {
        base.report.suspectTests.compactMap { test in
            renumbering[test.run].map { run in
                MutationSuspectTest(
                    name: test.name,
                    file: test.file,
                    run: run,
                    why: test.why,
                    files: test.files,
                    filesWithKills: test.filesWithKills
                )
            }
        }
    }

    /// The reason notes the merged tree `files` gives: how many paths were
    /// retested and carried, then, when there are any, the test files
    /// changed, the paths with no results and the unlisted ones.
    private func notes(_ files: [MutationFile]) -> [String] {
        let since = "since \(base.shortCommit)"
        let tested = files.count { $0.disposition == .tested }
        let carried = files.count { $0.disposition == .carried }
        let changedTests = files.count(where: \.changedTest)
        let unresolved = files.count { $0.disposition == .unresolved }
        let unlisted = files.count { $0.disposition == .unlisted }
        var notes = ["merged: \(Self.counted(tested, "file")) retested \(since), \(carried) carried"]
        if changedTests > 0 {
            notes.append(
                "\(Self.counted(changedTests, "test file")) changed \(since), "
                    + "so carried verdicts weren't retested against them"
            )
        }
        if unresolved > 0 {
            notes.append("\(Self.counted(unresolved, "file")) changed \(since) \(unresolved == 1 ? "has" : "have") "
                + "no results")
        }
        if unlisted > 0 {
            notes.append(
                "\(Self.counted(unlisted, "changed file")) \(unlisted == 1 ? "holds" : "hold") no mutant "
                    + "SwiftMutator tests, so \(unlisted == 1 ? "its" : "their") code no test ran isn't listed"
            )
        }
        return notes
    }
}
