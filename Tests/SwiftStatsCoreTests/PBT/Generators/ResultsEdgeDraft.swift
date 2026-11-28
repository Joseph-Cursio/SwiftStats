//
//  ResultsEdgeDraft.swift
//  SwiftStatsCoreTests
//
//  P15.1's results input: a SwiftMutator results.jsonl file whose every
//  number a key, a session or a run's outcome holds is an integer edge.
//  One format-4 header, its project the scanned file without a byte order
//  mark at its scanned hash, listing one mutant not covered; then one
//  `mutant` line in that file, killed by one test, with its own session,
//  exit status and failed-test count. Every other field is SwiftMutator
//  b16642de's, as `ResultsLineObjects` writes it.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// A results file whose numbers are integer edges.
struct ResultsEdgeDraft: Sendable, CustomTestStringConvertible {
    /// A mutant key's numbers.
    struct KeyNumbers: Hashable, Sendable {
        /// The 1-based line.
        let line: Int
        /// The 1-based UTF-8 column.
        let column: Int
        /// The occurrence: 0, or n for the nth repeat.
        let occurrence: Int

        /// The key of these numbers in the scanned file, of the drafts'
        /// operator.
        var key: MutantKey {
            MutantKey(
                path: IntegerEdgeGen.plainFile,
                operatorID: ResultsEdgeDraft.operatorID,
                line: line,
                column: column,
                occurrence: occurrence
            )
        }
    }

    /// The operator every drafted mutant is of.
    static let operatorID = "RelationalBoundary"
    /// The header's format.
    static let formatVersion = 4
    /// The time limit the header records, in seconds.
    static let timeoutSeconds = 20
    /// The mutants the header says were discovered: the tested one and the
    /// not-covered one.
    static let mutantsDiscovered = 2
    /// How long the tested mutant's run took, in seconds.
    static let durationSeconds = 0.5
    /// The file's line holding the `mutant` line (forced: the header is
    /// line 1).
    static let mutantLine = 2

    /// The header's session.
    let headerSession: Int
    /// The not-covered mutant the header lists.
    let notCovered: KeyNumbers
    /// The `mutant` line's session.
    let mutantSession: Int
    /// The tested mutant's key numbers.
    let tested: KeyNumbers
    /// The tested mutant's exit status.
    let exitStatus: Int
    /// How many tests failed against it, uncapped.
    let failedTestCount: Int

    /// The sessions, keys, exit status and failed-test count.
    var testDescription: String {
        "header session \(headerSession), not covered \(Self.shown(notCovered)); mutant session \(mutantSession), "
            + "tested \(Self.shown(tested)), exit status \(exitStatus), failed tests \(failedTestCount)"
    }

    /// `numbers` as `line:column #occurrence`.
    static func shown(_ numbers: KeyNumbers) -> String {
        "\(numbers.line):\(numbers.column) #\(numbers.occurrence)"
    }

    /// `numbers`' key parts as a line writes them.
    static func keyObject(_ numbers: KeyNumbers) -> [String: Any] {
        [
            "path": IntegerEdgeGen.plainFile,
            "line": numbers.line,
            "column": numbers.column,
            "occurrence": numbers.occurrence,
            "mutationOperatorId": operatorID
        ]
    }

    /// The header, its project the scanned file at `fileHash`.
    func header(fileHash: String) -> [String: Any] {
        let files = [IntegerEdgeGen.plainFile: fileHash]
        var notCoveredEntry = Self.keyObject(notCovered)
        notCoveredEntry["snapshot"] = ["after": "1 - 1", "before": "1 + 1", "description": "listed"]
        return [
            "kind": "header",
            "formatVersion": Self.formatVersion,
            "session": headerSession,
            "startedAt": "2026-11-21T09:00:00.000Z",
            "provenance": [
                "swiftMutator": ["executableSHA256": "5138cbf1", "version": "0.1.0"],
                "toolchain": [
                    "environment": ["DEVELOPER_DIR": "/Applications/Xcode.app"],
                    "testCommandVersion": "Swift"
                ]
            ],
            "operators": [Self.operatorID],
            "skipCoverage": false,
            "workers": 1,
            "timeoutSeconds": Self.timeoutSeconds,
            "stopsAtFirstFailure": false,
            "mutantsDiscovered": Self.mutantsDiscovered,
            "mutantsDropped": 0,
            "project": ["files": files, "treeSHA256": MutationTree.hash(of: files), "listedBy": "git"],
            "mutantsNotCovered": [notCoveredEntry]
        ]
    }

    /// The `mutant` line, in the scanned file at `fileHash`.
    func mutant(fileHash: String) -> [String: Any] {
        var object = Self.keyObject(tested)
        object.merge(
            [
                "kind": "mutant",
                "session": mutantSession,
                "outcome": "failed",
                "endedBy": "exited",
                "snapshot": ["after": "x >= 1", "before": "x > 1", "description": "tested"],
                "exitStatus": exitStatus,
                "durationSeconds": Self.durationSeconds,
                "killedBy": [["name": "checks()"]],
                "failedTestCount": failedTestCount,
                "fileSHA256": fileHash,
                "activated": true
            ]
        ) { _, field in field }
        return object
    }

    /// The file's bytes, the scanned file at `fileHash`: the header and the
    /// `mutant` line, each a line of JSON.
    func data(fileHash: String) throws -> Data {
        let lines = try [header(fileHash: fileHash), mutant(fileHash: fileHash)].map { object in
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data("\n".utf8)
        }
        return lines.reduce(Data(), +)
    }
}
