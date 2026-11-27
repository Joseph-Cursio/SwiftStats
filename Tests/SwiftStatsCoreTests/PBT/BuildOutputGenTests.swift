import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the build-output generator draws (design D14): from a fixed seed,
/// a thousand outputs reach each shape a build-output property reads, and
/// each antecedent it conditions on, an exact number of times, counted per
/// output (a property's chance per run). The current rules never draw a
/// shape awaiting a fix; the decided rules draw each. No line ends in a
/// carriage return, so CRLF goes only where the reader drops just the CR,
/// and no file passes the line cap. The counts hold under this engine's generator code and this
/// standard library; a change to either redraws them.
@Suite("Build output generator")
struct BuildOutputGenTests {
    /// The outputs each count draws.
    static let draws = 1_000
    /// The attempts allowed per draw: only scalar fragments reject a value
    /// (a surrogate), so a few are always enough at this seed, and a filter
    /// added later that rejects more fails here instead of hanging.
    static let attempts = 10
    /// The fixed seed every meta-test draws from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    /// What `output` has: each trait any line has, each kind of reading,
    /// and whether its diagnostics are stated, one is in both files (the
    /// reader keeps it once), one repeats within a file, a file is empty
    /// or at the line cap, and a line ends in a carriage return (never
    /// expected).
    static func labels(of output: GeneratedBuildOutput) -> [String] {
        let readings = Set(output.lines.map { reading(of: $0.reading) })
        let stderrDiagnostics = diagnostics(in: output.stderrLines)
        let logDiagnostics = diagnostics(in: output.logLines)
        var shapes: [String] = []
        if output.expected != nil {
            shapes.append("fully stated")
            if Set(stderrDiagnostics).isDisjoint(with: Set(logDiagnostics)) == false {
                shapes.append("diagnostic repeated across files")
            }
            if [stderrDiagnostics, logDiagnostics].contains(where: { Set($0).count < $0.count }) {
                shapes.append("diagnostic repeated within a file")
            }
        }
        if output.stderrLines.isEmpty {
            shapes.append("empty standard error")
        }
        if output.logLines.contains(where: { reading(of: $0.reading) == "diagnostic" }) {
            shapes.append("diagnostic in the log")
        }
        if max(output.stderrLines.count, output.logLines.count) == BuildOutputInterpreter.lineCap {
            shapes.append("at the line cap")
        }
        if output.lines.contains(where: { $0.written.last == UInt8(ascii: "\r") }) {
            shapes.append("a line ends in a carriage return")
        }
        return output.traits.map(\.rawValue) + readings.map { "reads as \($0)" } + shapes
    }

    /// The diagnostics `lines` read as, in order, repeats kept.
    static func diagnostics(in lines: [GeneratedBuildLine]) -> [BuildDiagnostic] {
        lines.compactMap { line in
            if case .diagnostic(let diagnostic) = line.reading {
                return diagnostic
            }
            return nil
        }
    }

    /// The name of `reading`'s kind.
    static func reading(of reading: BuildLineReading) -> String {
        switch reading {
        case .continuation:
            "continuation"

        case .diagnostic:
            "diagnostic"

        case .entry:
            "entry"

        case .ignored:
            "ignored"

        case .otherWarning:
            "other warning"

        case .skipped:
            "skipped"

        case .unparsedTiming:
            "unparsed timing"

        case .unstated:
            "unstated"
        }
    }

    /// How often each label comes up over `draws` outputs under `rules`,
    /// starting from `seeded`, and the most lines any file had.
    static func counts(_ rules: BuildOutputGen.Rules) throws -> (labels: [String: Int], longest: Int) {
        var random = seeded
        var counts: [String: Int] = [:]
        var longest = 0
        let generator = BuildOutputGen.output(rules)
        for _ in 0..<draws {
            let output = try generator.run(using: &random, limit: attempts)
            longest = max(longest, output.stderrLines.count, output.logLines.count)
            for label in labels(of: output) {
                counts[label, default: 0] += 1
            }
        }
        return (counts, longest)
    }

    @Test("the current rules reach every shape a property reads, and no shape awaiting a fix")
    func currentRules() throws {
        let counts = try Self.counts(.current)

        #expect(
            counts.labels == [
                "CRLF": 866,
                "at the line cap": 41,
                "crosses the continuation limit": 183,
                "decoy place": 170,
                "diagnostic in the log": 640,
                "diagnostic repeated across files": 90,
                "diagnostic repeated within a file": 1,
                "empty standard error": 93,
                "escaped": 794,
                "fully stated": 642,
                "inner suffix": 383,
                "inserted blank": 375,
                "invalid UTF-8": 86,
                "lone CR": 736,
                "macro origin": 86,
                "near header": 334,
                "no suffix": 402,
                "prepend": 472,
                "reads as continuation": 648,
                "reads as diagnostic": 809,
                "reads as entry": 753,
                "reads as ignored": 892,
                "reads as other warning": 442,
                "reads as skipped": 909,
                "reads as unparsed timing": 420,
                "reads as unstated": 358,
                "recorded": 428,
                "surplus": 463,
                "truncated escape": 313,
                "unknown place": 225,
                "unterminated": 306
            ]
        )
        #expect(counts.longest <= BuildOutputInterpreter.lineCap)
    }

    @Test("the decided rules also reach each shape awaiting a fix (B10, B23, B24)")
    func decidedRules() throws {
        let counts = try Self.counts(.decided)

        #expect(
            counts.labels == [
                "CRLF": 872,
                "at the line cap": 39,
                "crosses the continuation limit": 175,
                "decoy place": 175,
                "diagnostic in the log": 644,
                "diagnostic repeated across files": 95,
                "diagnostic repeated within a file": 1,
                "empty standard error": 95,
                "escaped": 833,
                "fully stated": 658,
                "inner suffix": 370,
                "inserted blank": 342,
                "invalid UTF-8": 83,
                "lone CR": 717,
                "macro origin": 92,
                "near header": 266,
                "no suffix": 421,
                "pending B10": 66,
                "pending B23": 465,
                "pending B24": 350,
                "prepend": 652,
                "reads as continuation": 654,
                "reads as diagnostic": 804,
                "reads as entry": 703,
                "reads as ignored": 875,
                "reads as other warning": 375,
                "reads as skipped": 888,
                "reads as unparsed timing": 490,
                "reads as unstated": 342,
                "recorded": 420,
                "surplus": 439,
                "truncated escape": 300,
                "unknown place": 221,
                "unterminated": 309
            ]
        )
        #expect(counts.longest <= BuildOutputInterpreter.lineCap)
    }
}
