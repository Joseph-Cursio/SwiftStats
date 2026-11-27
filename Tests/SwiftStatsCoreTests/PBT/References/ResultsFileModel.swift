//
//  ResultsFileModel.swift
//  SwiftStatsCoreTests
//
//  What a drafted results.jsonl (`ResultsFileDraft`) reads as, stated from
//  the reading rules (M6 design §2, `MutationResultsFile`'s header,
//  SwiftMutator's `Docs/results-file.md` "Reading it"), never from the
//  reader: the lines are read in order; a header whose `formatVersion` is
//  above 4 refuses the file where it stands, even when nothing else in it
//  reads; a header reads when it is whole and its `projectDelta`, if any,
//  rebuilds an earlier readable session's tree into the tree it names (the
//  pool's trees are distinct, so that is the same pool tree); a `mutant`,
//  `retired`, `control` or `end` line reads when it is whole, holds values
//  SwiftMutator writes, and its session has a readable header above it; a
//  `stopped` line reads when whole; a line of an unknown kind reads; a line
//  with no bytes isn't counted, but a lone CR is. The last readable
//  `mutant` line of a key wins and a readable `retired` line drops the key;
//  the last readable header's not-covered entries add each key no winning
//  line holds, its file hash from that header's tree. With no readable
//  header, the file is its last readable `stopped` line, or refused.
//  Keys compare as `MutantKey` compares them, so the two spellings of an
//  accented path are one key, as in the reader.
//  One rule is the reader's code, not the reading rules: a header in a
//  format below 1 isn't refused (`MutationResultsReader.add(_:)` refuses
//  only newer formats, as SwiftMutator's own `RecordedResults.swift`
//  does), where SwiftMutator's `Docs/results-file.md` "Compatibility" says
//  a reader should refuse a format it doesn't know. Until the user decides
//  which stands, the generator draws no format below 1 and
//  `ResultsFilePBT.formatsBelowOneRead` pins the code's behaviour.
//

@testable import SwiftStatsCore
import Testing

/// What a drafted results file reads as.
enum ResultsFileModel {
    /// How a file reads as a whole.
    enum Outcome: Equatable, Sendable, CustomTestStringConvertible {
        /// Refused by the first header in a newer format, this one.
        case newer(Int)
        /// Refused: no readable header and no readable `stopped` line.
        case noHeader
        /// Results, from at least one readable header.
        case results
        /// Only the `stopped` line tagged this.
        case stopped(tag: Int)

        /// The outcome, for a failure report.
        var testDescription: String {
            switch self {
            case let .newer(version):
                "refused by formatVersion \(version)"
            case .noHeader:
                "refused: no readable header and no readable stopped line"
            case .results:
                "results"
            case let .stopped(tag):
                "the stopped line of draft \(tag)"
            }
        }
    }

    /// What one physical line is to the reader.
    enum Label: Equatable, Sendable {
        /// No bytes: not a line it counts.
        case notCounted
        /// It reads.
        case readable
        /// It doesn't read, or belongs to no readable session: skipped.
        case unreadable
    }

    /// A mutant as a result names it: the text its line holds, the session
    /// that tested it (nil when not covered), and a not-covered mutant's
    /// file hash.
    struct Mutant: Equatable, Sendable, CustomTestStringConvertible {
        /// The hash digits a report shows.
        static let shownHashLength = 8

        /// `draft <tag>` for a tested mutant, `listed by draft <tag>` for a
        /// not-covered one.
        let marker: String
        /// The session that tested it; nil when not covered.
        let session: Int?
        /// A not-covered mutant's file hash in the last readable tree; nil
        /// for a tested one.
        let notCoveredFileSHA256: String?
        /// The code its snapshot replaces.
        let before: String
        /// What its snapshot puts in that code's place.
        let after: String

        /// The five, for a failure report.
        var testDescription: String {
            "\(marker), session \(session.map(String.init) ?? "none"), "
                + "hash \(notCoveredFileSHA256.map { String($0.prefix(Self.shownHashLength)) } ?? "none"), "
                + "\(before) -> \(after)"
        }
    }

    /// What a file reads as.
    struct Expected: Sendable {
        /// The file as a whole.
        let outcome: Outcome
        /// Each physical line's label, up to the line that refused the file.
        let labels: [Label]
        /// Every mutant, by key, when the file reads as results.
        let mutants: [MutantKey: Mutant]
        /// How many keys a winning `mutant` line holds.
        let tested: Int

        /// The 1-based numbers of the lines skipped.
        var unreadable: [Int] {
            labels.indices.filter { labels[$0] == .unreadable }.map { $0 + 1 }
        }
    }

    /// The newest format a header may be in: a header in a newer one
    /// refuses the file (the reading rules: formats 1 to 4). Older formats
    /// aren't refused, as the reader is built, which departs from the
    /// rules; the generator draws none (an open decision).
    static let newestFormatVersion = 4
    /// The keys whose fault keeps a header's format from being read.
    static let versionKeys: Set<String> = ["kind", "formatVersion"]
    /// The flaws that fall on a key and keep it from decoding.
    static let breakingKinds: Set<ResultsLineDraft.FlawKind> = [.absent, .mistyped, .null, .optionalMistyped]

    /// What `draft` reads as.
    static func expected(of draft: ResultsFileDraft) -> Expected {
        var state = State()
        for (index, line) in draft.lines.enumerated() {
            if case let .header(header) = line.draft, refuses(header) {
                return Expected(outcome: .newer(header.formatVersion), labels: state.labels, mutants: [:], tested: 0)
            }
            let isLast = index == draft.lines.count - 1
            state.labels.append(state.read(line, in: draft, unbroken: isLast == false || draft.finalBreak))
        }
        return state.expected(keys: draft.keys)
    }

    /// Whether `header` refuses the file: its format is newer, and its kind
    /// and format still decode.
    static func refuses(_ header: ResultsLineDraft.HeaderDraft) -> Bool {
        guard header.formatVersion > newestFormatVersion, header.flaw.kind != .cut else {
            return false
        }
        guard breakingKinds.contains(header.flaw.kind),
              let key = ResultsLineRenderer.flawedKey(of: .header(header), flaw: header.flaw)
        else {
            return true
        }
        return versionKeys.contains(key) == false
    }

    /// Whether `index` picks, from `list`, a value SwiftMutator writes:
    /// any but the list's last.
    static func isKnown(_ index: Int, in list: [String]) -> Bool {
        index % list.count < list.count - 1
    }
}
