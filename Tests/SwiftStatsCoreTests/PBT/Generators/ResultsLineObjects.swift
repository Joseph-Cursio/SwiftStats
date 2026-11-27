//
//  ResultsLineObjects.swift
//  SwiftStatsCoreTests
//
//  The JSON object of each drafted results line, before its flaw, shaped
//  as SwiftMutator b16642de writes it (`ResultsLines`): every key the
//  reader reads, optional ones included, and some it ignores. A line's tag
//  is in the text the reader keeps: a `mutant` line's snapshot description
//  is `draft <tag>`, a header's not-covered entries' `listed by draft
//  <tag>`, and a `stopped` line's step `draft <tag>`.
//

import Foundation
@testable import SwiftStatsCore

/// The JSON objects of drafted results lines.
enum ResultsLineObjects {
    /// The time limit a header records, in seconds.
    static let timeoutSeconds = 20
    /// The duration a `mutant` line records, in seconds.
    static let durationSeconds = 0.5
    /// The exit status a `mutant` line records.
    static let exitStatus = 1

    /// What a `mutant` line's description, or a `stopped` line's step,
    /// says for the line tagged `tag`.
    static func marker(_ tag: Int) -> String {
        "draft \(tag)"
    }

    /// What a header's not-covered entries' descriptions say for the
    /// header tagged `tag`.
    static func listedMarker(_ tag: Int) -> String {
        "listed by draft \(tag)"
    }

    /// The object of `line`, before its flaw, its keys from `keys`; empty
    /// for a line that isn't an object.
    static func object(of line: ResultsFileDraft.Line, keys: [MutantKey]) -> [String: Any] {
        switch line.draft {
        case let .header(header):
            return self.header(header, tag: line.tag, keys: keys)
        case let .mutant(mutant):
            return self.mutant(mutant, tag: line.tag, keys: keys)
        case let .retired(session, indices, _):
            return ["kind": "retired", "session": session, "keys": indices.map { keyObject(key(at: $0, in: keys)) }]
        case let .control(session, _):
            return [
                "kind": "control", "session": session, "number": 1, "outcome": "passed", "endedBy": "exited",
                "durationSeconds": durationSeconds
            ]
        case let .end(session, reason, _):
            return [
                "kind": "end", "session": session, "endedAt": "2026-11-21T09:01:00.000Z",
                "reason": ResultsLineRenderer.endReasons[reason % ResultsLineRenderer.endReasons.count],
                "detail": "SIGTERM", "recorded": 1
            ]
        case .stopped:
            return [
                "kind": "stopped", "step": marker(line.tag), "reason": "failed", "detail": "baselineTestFailed",
                "failedTests": [["location": "FailingTests.swift:4:5", "name": "alwaysFails()"]],
                "failedTestCount": 1, "projectPath": "/project"
            ]
        case .blank, .garbage, .unknown:
            return [:]
        }
    }

    /// The pool key at `index`, counted around the pool.
    static func key(at index: Int, in keys: [MutantKey]) -> MutantKey {
        keys[index % keys.count]
    }

    /// `key`'s five parts as a line writes them.
    static func keyObject(_ key: MutantKey) -> [String: Any] {
        [
            "path": key.path,
            "line": key.line,
            "column": key.column,
            "occurrence": key.occurrence,
            "mutationOperatorId": key.operatorID
        ]
    }

    /// The `header` object of `header`, tagged `tag`.
    private static func header(_ header: ResultsLineDraft.HeaderDraft, tag: Int, keys: [MutantKey]) -> [String: Any] {
        var object: [String: Any] = [
            "kind": "header",
            "formatVersion": header.formatVersion,
            "session": header.session,
            "startedAt": "2026-11-21T09:00:00.000Z",
            "provenance": [
                "swiftMutator": ["executableSHA256": "5138cbf1", "version": "0.1.0"],
                "toolchain": [
                    "environment": ["DEVELOPER_DIR": "/Applications/Xcode.app"],
                    "testCommandVersion": "Swift"
                ]
            ],
            "operators": ["RelationalBoundary", "SwapTernary"],
            "skipCoverage": false,
            "workers": 1,
            "timeoutSeconds": timeoutSeconds,
            "stopsAtFirstFailure": true,
            "mutantsDiscovered": keys.count,
            "mutantsDropped": 0
        ]
        let trees = ResultsLineRenderer.trees
        switch header.tree {
        case let .whole(index):
            let files = trees[index % trees.count]
            object["project"] = ["files": files, "treeSHA256": MutationTree.hash(of: files), "listedBy": "git"]
        case let .delta(base, target, honest):
            let from = trees[base % trees.count]
            let made = trees[target % trees.count]
            let claimed = honest ? made : trees[(target + 1) % trees.count]
            object["projectDelta"] = [
                "baseTreeSHA256": MutationTree.hash(of: from),
                "files": made.filter { from[$0.key] != $0.value },
                "removed": from.keys.filter { made[$0] == nil }.sorted(),
                "treeSHA256": MutationTree.hash(of: claimed),
                "listedBy": "git"
            ]
        case .noTree:
            break
        }
        if header.listsNotCovered {
            object["mutantsNotCovered"] = header.notCovered.map { index in
                var entry = keyObject(key(at: index, in: keys))
                entry["snapshot"] = ["after": "0", "before": "1", "description": listedMarker(tag)]
                return entry
            }
        }
        return object
    }

    /// The `mutant` object of `mutant`, tagged `tag`.
    private static func mutant(_ mutant: ResultsLineDraft.MutantDraft, tag: Int, keys: [MutantKey]) -> [String: Any] {
        var object = keyObject(key(at: mutant.key, in: keys))
        let fields: [String: Any] = [
            "kind": "mutant",
            "session": mutant.session,
            "outcome": ResultsLineRenderer.outcomes[mutant.outcome % ResultsLineRenderer.outcomes.count],
            "endedBy": ResultsLineRenderer.endings[mutant.ending % ResultsLineRenderer.endings.count],
            "snapshot": ["after": ">=", "before": ">", "description": marker(tag)],
            "exitStatus": exitStatus,
            "durationSeconds": durationSeconds,
            "killedBy": [["name": "checks()"]],
            "failedTestCount": 1,
            "fileSHA256": ResultsLineRenderer.hashA,
            "rerun": ["because": "timeout", "workers": 1],
            "leftOutWithOthers": false,
            "activated": true,
            "switchID": "Lib_1",
            "worker": 0
        ]
        object.merge(fields) { _, field in field }
        return object
    }
}
