import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the results-file generator draws (design D14), and what its model
/// says of hand-made files. From a fixed seed, a thousand files reach each
/// outcome and each antecedent P3.4 to P3.7 depend on an exact number of
/// times (files read as results, refused for want of a header, or a
/// `stopped` line; lines skipped and not counted; a lone CR; a key tested
/// twice, retired, retired then tested again; a not-covered mutant added;
/// a line of a session no header started; a `projectDelta` read and not
/// read; CRLF and no final break; each flaw), a thousand of P3.6's files
/// reach each refusal, and a thousand of P3.7's inputs read as results and
/// move a line. The counts hold under this engine's generator code and this
/// standard library; a change to either, or to a weight or list in
/// `ResultsFileGen`, redraws them.
@Suite("Results file generator")
struct ResultsFileGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: only drawn keys' scalars reject a
    /// value (a surrogate), so a few are always enough at this seed.
    static let attempts = 10
    /// The fixed seed the meta-tests draw from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    /// The classes `file` falls in.
    static func labels(of file: GeneratedResultsFile) -> [String] {
        let draft = file.draft
        let expected = ResultsFileModel.expected(of: draft)
        var labels = ["outcome: " + ResultsFilePBT.label(of: expected.outcome)]
        if case .newer = expected.outcome {
            labels += newerLabels(of: draft)
        }
        guard expected.outcome == .results else {
            return labels
        }
        labels += ResultsFilePBT.mutantLabels(of: draft, expected: expected)
            .filter { $0 != ResultsFilePBT.readsAsResults }
        labels += lineLabels(of: draft, expected: expected)
        return [
            (expected.unreadable.isEmpty == false, "a line skipped"),
            (expected.labels.contains(.notCounted), "a line not counted"),
            (draft.crlf, "CRLF"),
            (hasEndFaultyOnlyInReason(draft, expected: expected), "an end line whose only fault is its reason"),
            (draft.finalBreak == false, "no final break")
        ]
        .filter(\.0)
        .map(\.1) + Array(Set(labels)).sorted()
    }

    /// The classes of the lines of `draft`, read by the model as `expected`.
    static func lineLabels(of draft: ResultsFileDraft, expected: ResultsFileModel.Expected) -> [String] {
        var labels: [String] = []
        var retired: Set<MutantKey> = []
        for (line, label) in zip(draft.lines, expected.labels) {
            if let flaw = ResultsLineRenderer.flaw(of: line.draft), flaw.kind != .intact {
                labels.append("a line flawed: \(flaw.kind)")
            }
            switch line.draft {
            case .blank where label == .unreadable:
                labels.append("a lone CR skipped")
            case let .header(header):
                if case .delta = header.tree {
                    let unread = header.flaw.isReadable ? "a whole delta not read" : "a flawed delta"
                    labels.append(label == .readable ? "a delta read" : unread)
                }
            case let .mutant(mutant):
                let key = ResultsLineObjects.key(at: mutant.key, in: draft.keys)
                let valid = mutant.flaw.isReadable
                    && ResultsFileModel.isKnown(mutant.outcome, in: ResultsLineRenderer.outcomes)
                    && ResultsFileModel.isKnown(mutant.ending, in: ResultsLineRenderer.endings)
                if valid, label == .unreadable {
                    labels.append("a mutant line of a session no header started")
                }
                if label == .readable, retired.contains(key) {
                    labels.append("a key retired then tested again")
                }
            case let .retired(_, keys, _) where label == .readable:
                retired.formUnion(keys.map { ResultsLineObjects.key(at: $0, in: draft.keys) })
            default:
                break
            }
        }
        return labels
    }

    /// Whether `draft`, read by the model as `expected`, has an `end` line
    /// that would read but for its reason, one SwiftMutator doesn't write:
    /// the only input on which a reader that doesn't check the reason
    /// skips too few lines.
    static func hasEndFaultyOnlyInReason(_ draft: ResultsFileDraft, expected: ResultsFileModel.Expected) -> Bool {
        draft.lines.indices.contains { index in
            guard index < expected.labels.count, expected.labels[index] == .unreadable,
                  case let .end(session, reason, flaw) = draft.lines[index].draft,
                  ResultsFileModel.isKnown(reason, in: ResultsLineRenderer.endReasons) == false
            else {
                return false
            }
            var lines = draft.lines
            let known = ResultsLineDraft.end(session: session, reason: 0, flaw: flaw)
            lines[index] = ResultsFileDraft.Line(tag: lines[index].tag, draft: known)
            return ResultsFileModel.expected(of: draft.replacing(lines: lines)).labels[index] == .readable
        }
    }

    /// The classes of a file refused by a newer format: whether the refusing
    /// header reads otherwise, and whether a readable header is above it.
    static func newerLabels(of draft: ResultsFileDraft) -> [String] {
        var readableAbove = false
        for line in draft.lines {
            guard case let .header(header) = line.draft else {
                continue
            }
            if ResultsFileModel.refuses(header) {
                return [
                    header.flaw.isReadable ? "refused by a whole header" : "refused by a flawed header",
                    readableAbove ? "refused after a header" : "refused before any header"
                ]
            }
            let reads = header.flaw.isReadable && header.formatVersion <= ResultsFileModel.newestFormatVersion
            readableAbove = readableAbove || reads
        }
        return []
    }

    /// The count of each class over a thousand draws of `generator`, each
    /// draw's classes from `labels`.
    static func counts<Input>(
        _ generator: Generator<Input, AnySequence<Any>>,
        labels: (Input) -> [String]
    ) throws -> [String: Int] {
        var random = seeded
        var counts: [String: Int] = [:]
        for _ in 0..<draws {
            for label in labels(try generator.run(using: &random, limit: attempts)) {
                counts[label, default: 0] += 1
            }
        }
        return counts
    }

    @Test("a thousand files reach each outcome and each antecedent of P3.4 and P3.5 an exact number of times")
    func fileClasses() throws {
        let counts = try Self.counts(ResultsFileGen.file, labels: Self.labels(of:))

        #expect(counts == [
            "CRLF": 148,
            "a delta read": 67,
            "a flawed delta": 11,
            "a key retired then tested again": 76,
            "a key tested twice": 106,
            "a line flawed: absent": 51,
            "a line flawed: cut": 54,
            "a line flawed: mistyped": 50,
            "a line flawed: null": 57,
            "a line flawed: optionalMistyped": 60,
            "a line flawed: optionalNull": 51,
            "a line flawed: unknownKey": 65,
            "a line not counted": 159,
            "a line skipped": 500,
            "a lone CR skipped": 56,
            "a mutant line of a session no header started": 280,
            "a not-covered mutant added": 323,
            "a tested key retired": 78,
            "a whole delta not read": 125,
            "an end line whose only fault is its reason": 37,
            "no final break": 92,
            "outcome: refused: no header": 172,
            "outcome: results": 572,
            "outcome: stopped": 256
        ])
    }

    @Test("a thousand of P3.6's files reach each outcome and each kind of refusal an exact number of times")
    func anyFileClasses() throws {
        let counts = try Self.counts(ResultsFileGen.anyFile) { file in
            Self.labels(of: file).filter { $0.hasPrefix("outcome") || $0.hasPrefix("refused") }
        }

        #expect(counts == [
            "outcome: refused by a newer format": 216,
            "outcome: refused: no header": 189,
            "outcome: results": 350,
            "outcome: stopped": 245,
            "refused after a header": 166,
            "refused before any header": 50,
            "refused by a flawed header": 68,
            "refused by a whole header": 148
        ])
    }

    @Test("a thousand of P3.7's inputs read as results, and move a line, an exact number of times")
    func changeClasses() throws {
        let appended = try Self.counts(ResultsFileGen.appended.eraseToAny()) { input in
            ResultsFileModel.expected(of: input.file.draft).outcome == .results ? ["appended results"] : []
        }
        let reordered = try Self.counts(ResultsFileGen.reordered.eraseToAny()) { input in
            let results = ResultsFileModel.expected(of: input.file.draft).outcome == .results
            return [(input.moved, "moved"), (input.moved && results, "moved in results")].filter(\.0).map(\.1)
        }

        #expect(appended == [
            "appended results": 596
        ])
        #expect(reordered == [
            "moved": 297,
            "moved in results": 179
        ])
    }

    @Test("""
        a line appended to a CRLF file ending in an empty line with no line break takes that line's place: \
        breaking it first would skip it as a lone CR
        """)
    func appendingAfterUnbrokenBlank() {
        let header = ResultsFilePBT.header(session: 1, tree: 0, notCovered: [])
        let draft = ResultsFilePBT.draft([header, .blank], crlf: true, finalBreak: false)
        let broken = draft.replacing(lines: draft.lines + [ResultsFileDraft.Line(tag: 2, draft: .garbage(0))])

        let appended = ResultsFileGen.appending(0, to: draft)

        #expect(appended.lines.map(\.tag) == [0, 2])
        #expect(ResultsFileModel.expected(of: draft).unreadable.isEmpty)
        #expect(ResultsFileModel.expected(of: appended).unreadable == [2])
        #expect(ResultsFileModel.expected(of: broken).unreadable == [2, 3])
    }

    @Test("interleaving keeps each key's lines in order and moves no other line")
    func interleavingKeepsOrder() {
        let draft = ResultsFilePBT.draft([
            ResultsFilePBT.header(session: 1, tree: 0, notCovered: []),
            ResultsFilePBT.mutant(session: 1, key: 3),
            ResultsFilePBT.mutant(session: 1, key: 0),
            ResultsFilePBT.mutant(session: 1, key: 4),
            ResultsFilePBT.mutant(session: 1, key: 1),
            .blank,
            ResultsFilePBT.mutant(session: 1, key: 2)
        ])

        let lines = ResultsFileGen.interleaved(draft.lines, keys: draft.keys, picks: [1, 2, 0])

        // Keys 3 and 4 are one key, so draft 1 stays before draft 3.
        #expect(lines.map(\.tag) == [0, 2, 1, 3, 4, 5, 6])
    }

    @Test("the model reads a delta from a tree no session above records, or claiming another tree, as unreadable")
    func modelRefusesDeltas() {
        let delta = { (base: Int, honest: Bool) in
            ResultsLineDraft.header(ResultsLineDraft.HeaderDraft(
                session: 2,
                formatVersion: ResultsFileModel.newestFormatVersion,
                tree: .delta(base: base, target: 2, honest: honest),
                listsNotCovered: true,
                notCovered: [],
                flaw: ResultsFilePBT.intact
            ))
        }
        let draft = ResultsFilePBT.draft([
            ResultsFilePBT.header(session: 1, tree: 0, notCovered: []),
            delta(1, true),
            delta(0, false),
            ResultsFilePBT.mutant(session: 2, key: 0),
            delta(0, true),
            ResultsFilePBT.mutant(session: 2, key: 0)
        ])

        let expected = ResultsFileModel.expected(of: draft)

        #expect(expected.labels == [.readable, .unreadable, .unreadable, .unreadable, .readable, .readable])
        #expect(expected.mutants.values.map(\.marker) == ["draft 5"])
    }
}
