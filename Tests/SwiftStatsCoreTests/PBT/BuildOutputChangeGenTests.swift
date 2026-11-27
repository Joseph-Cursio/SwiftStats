import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the generators of changed build output draw (design D14): from a
/// fixed seed, a thousand inputs each reach every case P1.6 and P1.8
/// condition on an exact number of times, counted per input (a property's
/// chance per run). Escapes: lines newly wrapped, a sequence inside a
/// Character, a sequence whose last scalar joins the scalar after it (B24),
/// each kind of sequence, a wild line wrapped, a line already escaped or
/// not UTF-8 left as written, a byte order mark starting a wrapped line.
/// Splits: a split, none, one right after a message, one right after a
/// message with no ID, one before a timing line. Moves: a line moved,
/// none, one that ended a message, one written with an escape or with no
/// line break, into an empty log, after a log line with no line break. The
/// counts hold under this engine's generator code and this standard
/// library; a change to either, or to the build-output generator, redraws
/// them.
@Suite("Build output change generators")
struct BuildOutputChangeGenTests {
    /// The inputs each count draws.
    static let draws = 1_000
    /// The attempts allowed per draw, as `BuildOutputGenTests` allows.
    static let attempts = BuildOutputGenTests.attempts
    /// The fixed seed every count draws from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))
    /// A byte order mark's UTF-8 bytes.
    static let byteOrderMark = Array("\u{FEFF}".utf8)

    /// What `wrapped` has.
    static func labels(of wrapped: EscapeWrapGen.Wrapped) -> [String] {
        let original = wrapped.original.stderrLines + wrapped.original.logLines
        let lines = wrapped.stderrLines + wrapped.logLines
        let applied = lines.indices.filter { lines[$0].isWrapped }
        let offered = original.indices.filter { wrapped.wrap(at: $0) != nil }
        var labels = Set(applied.compactMap { wrapped.wrap(at: $0).map { "\($0.kind) written" } })
        let cases = [
            (applied.isEmpty == false, "a line newly wrapped"),
            (lines.contains(where: \.isInsideCharacter), "a sequence inside a Character"),
            (lines.contains(where: \.joins), "a sequence joining the scalar after it"),
            (applied.contains { original[$0].shape == .wild }, "a wild line wrapped"),
            (
                offered.contains { original[$0].written.contains(EscapeWrapGen.escapeByte) },
                "an escaped line left as written"
            ),
            (offered.contains { original[$0].traits.contains(.invalidUTF8) }, "a line not UTF-8 left as written"),
            (
                applied.contains { lines[$0].plain.starts(with: byteOrderMark) },
                "a wrapped line starting with a byte order mark"
            )
        ]
        labels.formUnion(cases.filter(\.0).map(\.1))
        return labels.sorted()
    }

    /// What `split` has.
    static func labels(of split: BuildOutputSplitGen.Split) -> [String] {
        guard let index = split.index else {
            return ["no place to split"]
        }
        let lines = split.sample.stderrLines
        var labels = ["a split"]
        if split.isAfterMessage {
            labels.append("a split right after a message")
        }
        if case .diagnostic(let diagnostic) = lines[index - 1].reading,
           diagnostic.identifier == nil, diagnostic.group == nil {
            labels.append("a split right after a header with no ID")
        }
        if case .entry = lines[index].reading {
            labels.append("a split before a timing line")
        }
        return labels
    }

    /// What `move` has.
    static func labels(of move: BuildOutputSplitGen.Move) -> [String] {
        guard let moved = move.moved else {
            return ["nothing to move"]
        }
        let log = move.sample.logLines
        let cases = [
            (true, "a timing line moved"),
            (move.endsMessage, "a moved line that ended a message"),
            (moved.traits.contains(.escaped), "a moved line written with an escape"),
            (moved.lineBreak.isEmpty, "a moved line with no line break"),
            (log.isEmpty, "moved into an empty log"),
            (
                move.position % (log.count + 1) == log.count && log.last?.lineBreak.isEmpty == true,
                "moved after a log line with no line break"
            )
        ]
        return cases.filter(\.0).map(\.1)
    }

    /// How often each label comes up over `draws` inputs from `generator`,
    /// labelled by `labels`, starting from `seeded`.
    static func counts<Input>(
        _ generator: Generator<Input, some Sequence>,
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

    @Test("a thousand wrapped outputs reach each case P1.6 conditions on an exact number of times")
    func wrapCounts() throws {
        let counts = try Self.counts(EscapeWrapGen.wrapped, labels: Self.labels(of:))

        #expect(counts == [
            "a line newly wrapped": 939,
            "a line not UTF-8 left as written": 26,
            "a sequence inside a Character": 763,
            "a sequence joining the scalar after it": 713,
            "a wild line wrapped": 126,
            "a wrapped line starting with a byte order mark": 9,
            "an escaped line left as written": 608,
            "csi written": 689,
            "oscBell written": 676,
            "oscTerminated written": 683,
            "truncated written": 703,
            "twoCharacter written": 695
        ])
    }

    @Test("a thousand split outputs reach each case P1.8's split conditions on an exact number of times")
    func splitCounts() throws {
        let counts = try Self.counts(BuildOutputSplitGen.split, labels: Self.labels(of:))

        #expect(counts == [
            "a split": 847,
            "a split before a timing line": 282,
            "a split right after a header with no ID": 86,
            "a split right after a message": 375,
            "no place to split": 153
        ])
    }

    @Test("a thousand moves reach each case P1.8's move conditions on an exact number of times")
    func moveCounts() throws {
        let counts = try Self.counts(BuildOutputSplitGen.move, labels: Self.labels(of:))

        #expect(counts == [
            "a moved line that ended a message": 199,
            "a moved line with no line break": 39,
            "a moved line written with an escape": 84,
            "a timing line moved": 761,
            "moved after a log line with no line break": 17,
            "moved into an empty log": 98,
            "nothing to move": 239
        ])
    }
}
