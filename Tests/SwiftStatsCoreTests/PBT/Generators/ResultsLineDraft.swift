//
//  ResultsLineDraft.swift
//  SwiftStatsCoreTests
//
//  One line of a generated results.jsonl (M6, design §2), as decisions:
//  its kind, its session, which key of the file's pool it names, which
//  tree a header records, and how the line is written otherwise than
//  SwiftMutator writes it (a flaw). Decisions, not text, so a shrunk line
//  is still a line of the same kind (design D7); `ResultsLineRenderer`
//  writes the text and `ResultsFileModel` says what the reader makes of it.
//

import Testing

/// One line of a generated results file, as decisions.
enum ResultsLineDraft: Sendable {
    /// A line with no bytes, which the reader doesn't count; under CRLF
    /// line breaks, a lone CR, which it does.
    case blank
    /// A `control` line of `session`.
    case control(session: Int, flaw: Flaw)
    /// An `end` line of `session` giving the reason at `reason` in
    /// `ResultsLineRenderer.endReasons`.
    case end(session: Int, reason: Int, flaw: Flaw)
    /// A line that never reads, at this index of
    /// `ResultsLineRenderer.garbage`.
    case garbage(Int)
    /// A `header` line.
    case header(HeaderDraft)
    /// A `mutant` line.
    case mutant(MutantDraft)
    /// A `retired` line of `session` naming the keys at these pool indices.
    case retired(session: Int, keys: [Int], flaw: Flaw)
    /// A `stopped` line.
    case stopped(Flaw)
    /// A line of a kind the reader doesn't know, at this index of
    /// `ResultsLineRenderer.unknownKinds`.
    case unknown(Int)

    /// How a line's JSON object is written otherwise than SwiftMutator
    /// writes it. `intact`, `optionalNull` and `unknownKey` leave the line
    /// readable; the others make it unreadable whatever else it says.
    enum FlawKind: Sendable, CaseIterable {
        /// A key the line's kind requires left out.
        case absent
        /// The line cut off after `slot` bytes, short of its last.
        case cut
        /// Written as SwiftMutator writes it.
        case intact
        /// A required key's value written with another JSON type.
        case mistyped
        /// A header's nested object, `provenance.toolchain` or
        /// `provenance.swiftMutator`, written as a string: both are keys
        /// SwiftMutator always writes, and a header that holds either
        /// mistyped doesn't read. A required key's value mistyped, for any
        /// other kind of line.
        case nestedMistyped
        /// A required key's value written as `null`.
        case null
        /// An optional key's value written with another JSON type; a
        /// required key's, for a kind with no optional key read.
        case optionalMistyped
        /// An optional key's value written as `null`, which reads as
        /// absent.
        case optionalNull
        /// Keys no reader knows added: SwiftMutator may add keys.
        case unknownKey
    }

    /// A line's flaw: its kind and which key or byte it falls on.
    struct Flaw: Sendable, CustomTestStringConvertible {
        /// The flaws that leave a line readable.
        static let readableKinds: Set<FlawKind> = [.intact, .optionalNull, .unknownKey]

        /// Its kind.
        let kind: FlawKind
        /// Which key it falls on, counted around the kind's key list, or
        /// where a cut falls, counted around the line's bytes.
        let slot: Int

        /// Whether the flaw leaves its line readable.
        var isReadable: Bool {
            Self.readableKinds.contains(kind)
        }

        /// The kind and slot.
        var testDescription: String {
            kind == .intact ? "intact" : "\(kind) at \(slot)"
        }
    }

    /// The tree a header records.
    enum TreeDraft: Sendable {
        /// `projectDelta` from the pool's tree `base` to its tree `target`,
        /// naming the tree it makes when `honest`, else another pool tree.
        case delta(base: Int, target: Int, honest: Bool)
        /// Neither `project` nor `projectDelta`.
        case noTree
        /// `project`: the pool's tree at this index.
        case whole(Int)
    }

    /// A `header` line.
    struct HeaderDraft: Sendable {
        /// Its session.
        let session: Int
        /// Its `formatVersion`.
        let formatVersion: Int
        /// The tree it records.
        let tree: TreeDraft
        /// Whether it writes `mutantsNotCovered`.
        let listsNotCovered: Bool
        /// The pool indices of its `mutantsNotCovered` entries.
        let notCovered: [Int]
        /// Its flaw.
        let flaw: Flaw
    }

    /// A `mutant` line.
    struct MutantDraft: Sendable {
        /// Its session.
        let session: Int
        /// The pool index of its key.
        let key: Int
        /// The index of its outcome in `ResultsLineRenderer.outcomes`.
        let outcome: Int
        /// The index of its ending in `ResultsLineRenderer.endings`.
        let ending: Int
        /// Its flaw.
        let flaw: Flaw
    }
}
