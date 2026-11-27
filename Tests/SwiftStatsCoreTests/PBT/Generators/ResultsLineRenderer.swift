//
//  ResultsLineRenderer.swift
//  SwiftStatsCoreTests
//
//  Writes a drafted results line (`ResultsLineDraft`) as SwiftMutator
//  writes one (`ResultsLines`, `Docs/results-file.md` in SwiftMutator):
//  a JSON object, keys sorted and slashes unescaped, holding every key the
//  reader reads and some it ignores, then its flaw applied. The lists a
//  line chooses from end with one value no SwiftMutator writes, so the
//  model can say which choices read. A tree is one of a pool of distinct
//  trees, so a `projectDelta` either rebuilds an earlier session's tree
//  into the tree it names or doesn't, by construction. The pool's paths
//  are spelled one way each: a tree holding both spellings of one path
//  can't come from a file system that folds them.
//

import Foundation
@testable import SwiftStatsCore

/// Writes drafted results lines.
enum ResultsLineRenderer {
    /// The outcomes a `mutant` line chooses from; all but the last are
    /// SwiftMutator's (`MutationVerdict` reads those six).
    static let outcomes = ["failed", "passed", "timeout", "buildError", "noCoverage", "runtimeError", "vanished"]
    /// The endings a `mutant` line chooses from; all but the last are
    /// SwiftMutator's.
    static let endings = [
        "exited", "timedOut", "couldNotRun", "cancelled", "stoppedAtCrash", "stoppedAtFailedTest", "melted"
    ]
    /// The reasons an `end` line chooses from; all but the last are
    /// SwiftMutator's.
    static let endReasons = ["finished", "interrupted", "aborted", "paused"]
    /// Kinds no reader knows: one SwiftMutator writes that SwiftStats
    /// ignores, one a later SwiftMutator might write, and `header`
    /// capitalised.
    static let unknownKinds = ["propertyRerun", "someday", "Header"]
    /// Lines that never read: not JSON, a lone CR, blanks, NULs, a top-level
    /// array, an object with no kind or a kind that isn't a string, junk
    /// after an object, and a byte that isn't UTF-8.
    static let garbage: [[UInt8]] = [
        Array("not json".utf8),
        [carriageReturn],
        Array("   ".utf8),
        [UInt8](repeating: 0, count: nulCount),
        Array(#"["header"]"#.utf8),
        Array(#"{"no":"kind"}"#.utf8),
        Array(#"{"formatVersion":9,"kind":7}"#.utf8),
        Array(#"{"kind":"end"} x"#.utf8),
        [invalidByte] + Array(#"{"kind":"someday"}"#.utf8)
    ]
    /// The pool of trees headers record, each distinct, so each has its own
    /// hash.
    static let trees: [[String: String]] = [
        [libraryPath: hashA],
        [libraryPath: hashB, cafePath: hashC],
        [libraryPath: hashA, cafePath: hashC, oddPath: MutationTree.linkPrefix + hashD],
        [:]
    ]
    /// The library file the pool's keys and trees name.
    static let libraryPath = "Sources/Lib/Lib.swift"
    /// A path with a combining mark, decomposed in the trees.
    static let cafePath = "Sources/Cafe\u{301}.swift"
    /// A path holding a space, a colon and ` (#`.
    static let oddPath = "My Sources/a:b (#3).swift"
    /// A file hash.
    static let hashA = String(repeating: "a", count: hashLength)
    /// Another.
    static let hashB = String(repeating: "b", count: hashLength)
    /// Another.
    static let hashC = String(repeating: "c", count: hashLength)
    /// Another.
    static let hashD = String(repeating: "d", count: hashLength)
    /// The hex digits of a SHA-256 (forced).
    static let hashLength = 64
    /// The NULs of a NUL-padded line (assumed: any run is as good).
    static let nulCount = 12
    /// A byte that never appears in UTF-8 (forced).
    static let invalidByte: UInt8 = 0xFF
    /// CR (forced).
    static let carriageReturn: UInt8 = 0x0D
    /// LF (forced).
    static let lineFeed: UInt8 = 0x0A
    /// What a value of a required string key is written as when mistyped.
    static let mistypedNumber = 7
    /// What any other value is written as when mistyped.
    static let mistypedText = "x"
    /// The `formatVersion` an unknown-key flaw adds to a line other than a
    /// header, which only a header's is read.
    static let strayFormatVersion = 9

    /// The keys a line of each kind must hold, each with a value of the
    /// type the reader decodes; `kind` first.
    static func requiredKeys(of draft: ResultsLineDraft) -> [String] {
        switch draft {
        case .header:
            [
                "kind", "formatVersion", "session", "startedAt", "provenance", "operators", "skipCoverage",
                "workers", "stopsAtFirstFailure", "mutantsDiscovered"
            ]
        case .mutant:
            [
                "kind", "session", "path", "line", "column", "occurrence", "mutationOperatorId", "snapshot",
                "outcome", "endedBy"
            ]
        case .retired:
            ["kind", "session", "keys"]
        case .control:
            ["kind", "session", "outcome"]
        case .end:
            ["kind", "session", "endedAt", "reason"]
        case .stopped:
            ["kind", "step", "reason"]
        case .blank, .garbage, .unknown:
            []
        }
    }

    /// The nested keys a line of each kind must hold, as dotted paths, each
    /// an object the reader decodes: a header's `provenance.toolchain` and
    /// `provenance.swiftMutator`. Only a `nestedMistyped` flaw falls on
    /// them: a header with no `provenance.toolchain` reads, as the reader
    /// is built (an open question, so none is drawn).
    static func nestedKeys(of draft: ResultsLineDraft) -> [String] {
        if case .header = draft {
            return ["provenance.toolchain", "provenance.swiftMutator"]
        }
        return []
    }

    /// The optional keys a line of each kind holds whose type the reader
    /// checks, and that change nothing else when `null`.
    static func optionalKeys(of draft: ResultsLineDraft) -> [String] {
        switch draft {
        case .header:
            ["timeoutSeconds", "mutantsDropped"]
        case .mutant:
            [
                "exitStatus", "durationSeconds", "killedBy", "failedTestCount", "fileSHA256", "rerun",
                "leftOutWithOthers", "activated"
            ]
        case .end:
            ["detail"]
        case .stopped:
            ["detail", "failedTests", "failedTestCount"]
        case .blank, .control, .garbage, .retired, .unknown:
            []
        }
    }

    /// The key `flaw` falls on in a line drafted as `draft`, a nested one
    /// as a dotted path; nil for a flaw that falls on no key (intact, a
    /// cut, unknown keys), or on an optional key's `null`.
    static func flawedKey(of draft: ResultsLineDraft, flaw: ResultsLineDraft.Flaw) -> String? {
        let required = requiredKeys(of: draft)
        let optional = optionalKeys(of: draft)
        switch flaw.kind {
        case .absent, .mistyped, .null:
            return required.isEmpty ? nil : required[flaw.slot % required.count]
        case .nestedMistyped:
            let nested = nestedKeys(of: draft)
            if nested.isEmpty {
                return required.isEmpty ? nil : required[flaw.slot % required.count]
            }
            return nested[flaw.slot % nested.count]
        case .optionalMistyped:
            if optional.isEmpty {
                return required.isEmpty ? nil : required[flaw.slot % required.count]
            }
            return optional[flaw.slot % optional.count]
        case .optionalNull:
            return optional.isEmpty ? nil : optional[flaw.slot % optional.count]
        case .cut, .intact, .unknownKey:
            return nil
        }
    }

    /// The bytes of `line`, its keys from `keys`: its JSON object with its
    /// flaw applied, a garbage line's bytes, or none for a blank line.
    static func bytes(of line: ResultsFileDraft.Line, keys: [MutantKey]) -> [UInt8] {
        switch line.draft {
        case .blank:
            return []
        case let .garbage(index):
            return garbage[index % garbage.count]
        case let .unknown(index):
            return encoded([
                "kind": unknownKinds[index % unknownKinds.count],
                "session": 1,
                "formatVersion": strayFormatVersion
            ])
        default:
            break
        }
        guard let flaw = flaw(of: line.draft) else {
            return []
        }
        var object = ResultsLineObjects.object(of: line, keys: keys)
        apply(flaw, to: &object, draft: line.draft)
        let bytes = encoded(object)
        guard flaw.kind == .cut, bytes.count > 1 else {
            return bytes
        }
        return Array(bytes.prefix(1 + flaw.slot % (bytes.count - 1)))
    }

    /// The flaw of a drafted line of a kind that has one.
    static func flaw(of draft: ResultsLineDraft) -> ResultsLineDraft.Flaw? {
        switch draft {
        case let .header(header):
            header.flaw
        case let .mutant(mutant):
            mutant.flaw
        case let .retired(_, _, flaw), let .control(_, flaw), let .end(_, _, flaw), let .stopped(flaw):
            flaw
        case .blank, .garbage, .unknown:
            nil
        }
    }

    /// `object`, a line drafted as `draft`, with `flaw` applied.
    private static func apply(_ flaw: ResultsLineDraft.Flaw, to object: inout [String: Any], draft: ResultsLineDraft) {
        let key = flawedKey(of: draft, flaw: flaw)
        switch flaw.kind {
        case .absent:
            if let key {
                object.removeValue(forKey: key)
            }
        case .mistyped, .nestedMistyped, .optionalMistyped:
            if let key {
                mistype(key.split(separator: ".").map(String.init), in: &object)
            }
        case .null, .optionalNull:
            if let key {
                object[key] = NSNull()
            }
        case .unknownKey:
            object["futureKey"] = ["nested": [1, "two"]]
            if case .header = draft {
                break
            }
            object["formatVersion"] = strayFormatVersion
        case .cut, .intact:
            break
        }
    }

    /// `object` with the value at the key `path`, nested objects' keys
    /// first, written with another JSON type.
    private static func mistype(_ path: [String], in object: inout [String: Any]) {
        guard let key = path.first else {
            return
        }
        guard path.count > 1, var nested = object[key] as? [String: Any] else {
            object[key] = object[key] is String ? mistypedNumber : mistypedText
            return
        }
        mistype(Array(path.dropFirst()), in: &nested)
        object[key] = nested
    }

    /// `object` as one JSON line, keys sorted and slashes unescaped, as
    /// SwiftMutator writes it.
    static func encoded(_ object: [String: Any]) -> [UInt8] {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        return Array((try? JSONSerialization.data(withJSONObject: object, options: options)) ?? Data())
    }
}
