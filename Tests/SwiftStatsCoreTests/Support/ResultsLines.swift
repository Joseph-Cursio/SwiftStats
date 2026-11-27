//
//  ResultsLines.swift
//  SwiftStatsCoreTests
//
//  Hand-written lines of SwiftMutator's results.jsonl (M6, design §2),
//  shaped as SwiftMutator b16642de writes them, for the reader's tests:
//  headers with a whole tree or a `projectDelta`, `mutant`, `retired`,
//  `control`, `end` and `stopped` lines. Keys are sorted and slashes
//  unescaped, as SwiftMutator writes them.
//

import Foundation
@testable import SwiftStatsCore

/// Builds results-file lines.
enum ResultsLines {
    /// A tree recorded as what changed since `base`.
    struct Delta {
        /// The earlier tree.
        var base: [String: String]
        /// The files added or changed.
        var files: [String: String]
        /// The paths removed.
        var removed: [String] = []
        /// The tree hash it claims to make; by default the one it makes.
        var claimedTreeSHA256: String?
    }

    /// A header's session and contents, for `header(_:)`.
    struct Header {
        /// The session.
        var session = 1
        /// The format.
        var formatVersion = 4
        /// Mutants discovered.
        var discovered = 0
        /// The whole tree, written when `delta` is nil.
        var tree: [String: String] = [:]
        /// The tree as a change.
        var delta: Delta?
        /// Whether `mutantsNotCovered` is written.
        var listsNotCovered = true
        /// Its keys.
        var notCovered: [MutantKey] = []
        /// Mutants tested at once.
        var workers = 1
        /// The time limit per mutant, written when not nil.
        var timeoutSeconds: Int? = ResultsLines.timeoutSeconds
        /// Whether coverage was off.
        var skipCoverage = false
        /// Whether a mutant's run stopped at its first failed test.
        var stopsAtFirstFailure = true
        /// `mutantsDropped`, written when not nil.
        var dropped: Int?
        /// The operators.
        var operators = ["RelationalBoundary", "SwapTernary"]
        /// The SwiftMutator build's hash.
        var executableSHA256 = "5138cbf1"
    }

    /// A session's `end` line, for `end(_:)`.
    struct End {
        /// The session.
        var session = 1
        /// `finished`, `aborted` or `interrupted`.
        var reason = "finished"
        /// The abort's code or the signal's name, when written.
        var detail: String?
    }

    /// A mutant's key and outcome, for `mutant(_:)`.
    struct Mutant {
        /// The key's path.
        var path = "Sources/Lib/Lib.swift"
        /// The key's line.
        var line = 3
        /// The key's column.
        var column = 9
        /// The key's occurrence.
        var occurrence = 0
        /// The key's operator.
        var operatorID = "RelationalBoundary"
        /// The raw outcome.
        var outcome = "failed"
        /// How the run ended.
        var endedBy = "exited"
        /// The session.
        var session = 1
        /// `activated`, when written.
        var activated: JSONFlag?
        /// The tests named, when written.
        var killedBy: [String] = []
        /// `failedTestCount`, when written.
        var failedTestCount: Int?
        /// `fileSHA256`, when written.
        var fileSHA256: String?
        /// `rerun.because`, when written.
        var rerunBecause: String?
        /// Whether `reusedFrom` is written.
        var reused = false
        /// `leftOutWithOthers`, when written.
        var leftOutWithOthers: JSONFlag?
    }

    /// The time limit a header records by default, in seconds.
    static let timeoutSeconds = 20
    /// The duration every `mutant` line records, in seconds.
    static let durationSeconds = 0.5
    /// The offset every `mutant` line records.
    static let utf8Offset = 10
    /// The test duration every `end` line records, in seconds.
    static let testDurationSeconds = 60

    /// The tree hash a header's `project` gives `files`.
    static func treeHash(_ files: [String: String]) -> String {
        MutationTree.hash(of: files)
    }

    /// The header line `header` describes.
    static func header(_ header: Header) -> String {
        var record: [String: Any] = [
            "kind": "header",
            "formatVersion": header.formatVersion,
            "session": header.session,
            "startedAt": "2026-11-21T09:00:0\(header.session).000Z",
            "provenance": [
                "arguments": ["run"],
                "host": "host",
                "processIdentifier": 1,
                "swiftMutator": ["executableSHA256": header.executableSHA256, "version": "0.1.0"],
                "toolchain": [
                    "environment": ["DEVELOPER_DIR": "/Applications/Xcode.app"],
                    "testCommandVersion": "Swift"
                ]
            ],
            "operators": header.operators,
            "skipCoverage": header.skipCoverage,
            "workers": header.workers,
            "stopsAtFirstFailure": header.stopsAtFirstFailure,
            "mutantsDiscovered": header.discovered,
            "mutantsToTest": header.discovered
        ]
        if let timeout = header.timeoutSeconds {
            record["timeoutSeconds"] = timeout
        }
        if let dropped = header.dropped {
            record["mutantsDropped"] = dropped
        }
        if let delta = header.delta {
            record["projectDelta"] = projectDelta(delta)
        } else {
            record["project"] = [
                "excluded": [String](),
                "files": header.tree,
                "listedBy": "git",
                "treeSHA256": treeHash(header.tree)
            ]
        }
        if header.listsNotCovered {
            record["mutantsNotCovered"] = header.notCovered.map(notCoveredEntry)
        }
        return line(record)
    }

    /// The `projectDelta` `delta` describes.
    private static func projectDelta(_ delta: Delta) -> [String: Any] {
        var rebuilt = delta.base.merging(delta.files) { $1 }
        for path in delta.removed {
            rebuilt.removeValue(forKey: path)
        }
        return [
            "baseTreeSHA256": treeHash(delta.base),
            "excluded": [String](),
            "files": delta.files,
            "listedBy": "git",
            "removed": delta.removed,
            "treeSHA256": delta.claimedTreeSHA256 ?? treeHash(rebuilt)
        ]
    }

    /// The `mutantsNotCovered` entry of `key`.
    private static func notCoveredEntry(_ key: MutantKey) -> [String: Any] {
        [
            "path": key.path,
            "line": key.line,
            "column": key.column,
            "occurrence": key.occurrence,
            "mutationOperatorId": key.operatorID,
            "snapshot": ["after": "0", "before": "1", "description": "replaced the return value with 0"]
        ]
    }

    /// A `mutant` line for `mutant`.
    static func mutant(_ mutant: Mutant) -> String {
        var record: [String: Any] = [
            "kind": "mutant",
            "session": mutant.session,
            "path": mutant.path,
            "line": mutant.line,
            "column": mutant.column,
            "occurrence": mutant.occurrence,
            "mutationOperatorId": mutant.operatorID,
            "outcome": mutant.outcome,
            "endedBy": mutant.endedBy,
            "durationSeconds": durationSeconds,
            "finishedAt": "2026-11-21T09:00:10.000Z",
            "switchID": "Lib_1",
            "utf8Offset": utf8Offset,
            "worker": 0,
            "snapshot": ["after": ">=", "before": ">", "description": "changed > to >="]
        ]
        if let activated = mutant.activated {
            record["activated"] = activated.value
        }
        if mutant.killedBy.isEmpty == false || mutant.failedTestCount != nil {
            record["killedBy"] = mutant.killedBy.map { ["name": $0] }
        }
        if let count = mutant.failedTestCount {
            record["failedTestCount"] = count
        }
        if let hash = mutant.fileSHA256 {
            record["fileSHA256"] = hash
        }
        if let because = mutant.rerunBecause {
            record["rerun"] = ["because": because, "workers": 1]
        }
        if mutant.reused {
            record["reusedFrom"] = ["resultsFile": "/earlier/results.jsonl", "session": 1]
        }
        if let leftOut = mutant.leftOutWithOthers {
            record["leftOutWithOthers"] = leftOut.value
        }
        return line(record)
    }

    /// A `retired` line of session `session` for `keys`.
    static func retired(session: Int, keys: [MutantKey]) -> String {
        line([
            "kind": "retired",
            "session": session,
            "keys": keys.map { key in
                [
                    "path": key.path,
                    "line": key.line,
                    "column": key.column,
                    "occurrence": key.occurrence,
                    "mutationOperatorId": key.operatorID
                ] as [String: Any]
            }
        ])
    }

    /// A `control` line of session 1 with `outcome`.
    static func control(_ outcome: String) -> String {
        control(session: 1, outcome: outcome)
    }

    /// A `control` line of session `session` with `outcome`.
    static func control(session: Int, outcome: String) -> String {
        line([
            "kind": "control",
            "session": session,
            "number": 1,
            "afterMutants": 1,
            "outcome": outcome,
            "endedBy": "exited",
            "durationSeconds": durationSeconds,
            "worker": 0,
            "finishedAt": "2026-11-21T09:00:20.000Z",
            "log": "control run 1.log"
        ])
    }

    /// The `end` line `end` describes.
    static func end(_ end: End) -> String {
        var record: [String: Any] = [
            "kind": "end",
            "session": end.session,
            "endedAt": "2026-11-21T09:01:0\(end.session).000Z",
            "reason": end.reason,
            "recorded": 1,
            "testDurationSeconds": testDurationSeconds
        ]
        if let detail = end.detail {
            record["detail"] = detail
        }
        return line(record)
    }

    /// A `stopped` line: a failed baseline whose one failing test is
    /// `test`.
    static func stopped(test: String) -> String {
        line([
            "kind": "stopped",
            "step": "baseline",
            "reason": "failed",
            "detail": "baselineTestFailed",
            "failedTests": [["location": "FailingTests.swift:4:5", "name": test]],
            "failedTestCount": 1,
            "startedAt": "2026-11-21T09:00:00.000Z",
            "stoppedAt": "2026-11-21T09:00:05.000Z",
            "projectPath": "/project",
            "logDirectory": "/logs"
        ])
    }

    /// `lines` as a file's bytes, each ended by a line break.
    static func file(_ lines: [String]) -> Data {
        Data(lines.map { $0 + "\n" }.joined().utf8)
    }

    /// The results `lines` hold, read; fails when they hold none.
    static func results(_ lines: [String]) throws -> MutationResults {
        guard case .results(let results) = try MutationResultsFile.read(file(lines)) else {
            throw MutationFailure(description: "no results")
        }
        return results
    }

    /// `record` as one JSON line, keys sorted and slashes unescaped.
    private static func line(_ record: [String: Any]) -> String {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? JSONSerialization.data(withJSONObject: record, options: options)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
