import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the timing-entry generator draws (design D14): from a fixed seed,
/// a thousand entries reach each class P1.4's round trip depends on an
/// exact number of times: expressions and function bodies, `<invalid
/// loc>`, the build-output generator's paths and paths of any scalars, a
/// path holding a colon, a line break, an escape or a Prepend scalar just
/// before the line's colon, the largest line and column, each form a time
/// is written in (as the value allows it), leading zeros before a time and
/// before a line, and the edge times. The counts hold under this engine's
/// generator code and this standard library; a change to either, or to a
/// weight or list in `TimingEntryGen`, redraws them.
@Suite("Timing entry generator")
struct TimingEntryGenTests {
    /// The draws the meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: only scalars reject a value (a
    /// surrogate), so a few are always enough at this seed.
    static let attempts = 10
    /// The fixed seed the meta-test draws from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))
    /// The Prepend scalars the generators draw.
    static let prependScalars = Set(UnicodeGen.prepend.joined().unicodeScalars)

    /// The classes `line` falls in.
    static func labels(of line: TimingEntryGen.Line) -> [String] {
        let entry = line.entry
        var labels = [entry.kind == .function ? "function body" : "expression"]
        if let place = entry.place {
            let generated = BuildOutputGen.roots.contains { place.path.hasPrefix($0 + "/") }
            labels.append(generated ? "generated path" : "path of any scalars")
            let scalars = place.path.unicodeScalars
            labels += [
                (scalars.contains(":"), "path with a colon"),
                (scalars.contains("\n") || scalars.contains("\r"), "path with a line break"),
                (scalars.contains("\u{1B}"), "path with an escape"),
                (scalars.last.map(prependScalars.contains) == true, "Prepend before the colon"),
                (place.line == Int.max, "largest line"),
                (place.column == Int.max, "largest column")
            ]
            .filter(\.0)
            .map(\.1)
        } else {
            labels.append("invalid loc")
        }
        let time = BuildLineRenderer.time(entry.hundredths, style: line.style)
        let digits = time.dropLast(BuildLineRenderer.unit.count)
        let fraction = digits.split(separator: ".", omittingEmptySubsequences: false)
        labels.append("time with \(fraction.count == 1 ? 0 : fraction[1].count) fraction digits")
        if fraction[0].count > 1, fraction[0].hasPrefix("0") {
            labels.append("time with a leading zero")
        }
        if line.style.paddedNumbers, entry.place != nil {
            labels.append("line with a leading zero")
        }
        if entry.hundredths == 0 || entry.hundredths == TimingEntryGen.largestHundredths {
            labels.append("edge time")
        }
        return labels
    }

    @Test("a thousand timing entries reach each class P1.4 depends on an exact number of times")
    func classCounts() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let line = try TimingEntryGen.line.run(using: &random, limit: Self.attempts)
            for label in Self.labels(of: line) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "Prepend before the colon": 84,
            "edge time": 62,
            "expression": 520,
            "function body": 480,
            "generated path": 400,
            "invalid loc": 198,
            "largest column": 47,
            "largest line": 51,
            "line with a leading zero": 152,
            "path of any scalars": 402,
            "path with a colon": 237,
            "path with a line break": 186,
            "path with an escape": 135,
            "time with 0 fraction digits": 36,
            "time with 1 fraction digits": 67,
            "time with 2 fraction digits": 897,
            "time with a leading zero": 161
        ])
    }
}
