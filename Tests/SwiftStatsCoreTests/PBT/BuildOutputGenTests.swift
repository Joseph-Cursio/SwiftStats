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
    /// reader keeps it once), one repeats within a file, two function
    /// bodies at one place have times to sum, a file is empty or at the
    /// line cap, and a line ends in a carriage return (never
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
        if BuildOutputGen.repeatsBody(output.entries) {
            shapes.append("a function body's times to sum")
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
                "CRLF": 896,
                "a function body's times to sum": 329,
                "at the line cap": 41,
                "crosses the continuation limit": 168,
                "decoy place": 153,
                "diagnostic in the log": 651,
                "diagnostic repeated across files": 81,
                "diagnostic repeated within a file": 1,
                "empty declaration": 374,
                "empty standard error": 86,
                "escaped": 801,
                "fully stated": 631,
                "inner suffix": 327,
                "inserted blank": 419,
                "invalid UTF-8": 81,
                "lone CR": 739,
                "macro origin": 76,
                "near header": 308,
                "no suffix": 401,
                "prepend": 499,
                "reads as continuation": 630,
                "reads as diagnostic": 793,
                "reads as entry": 760,
                "reads as ignored": 862,
                "reads as other warning": 405,
                "reads as skipped": 913,
                "reads as unparsed timing": 554,
                "reads as unstated": 369,
                "recorded": 388,
                "surplus": 428,
                "truncated escape": 321,
                "unknown place": 213,
                "unterminated": 308
            ]
        )
        #expect(counts.longest <= BuildOutputInterpreter.lineCap)
    }

    @Test("the decided rules also reach each shape awaiting a fix (B10, B23, B24)")
    func decidedRules() throws {
        let counts = try Self.counts(.decided)

        #expect(
            counts.labels == [
                "CRLF": 880,
                "a function body's times to sum": 318,
                "at the line cap": 42,
                "crosses the continuation limit": 162,
                "decoy place": 116,
                "diagnostic in the log": 632,
                "diagnostic repeated across files": 87,
                "diagnostic repeated within a file": 1,
                "empty declaration": 331,
                "empty standard error": 82,
                "escaped": 826,
                "fully stated": 685,
                "inner suffix": 321,
                "inserted blank": 315,
                "invalid UTF-8": 77,
                "lone CR": 698,
                "macro origin": 81,
                "near header": 252,
                "no suffix": 398,
                "pending B10": 82,
                "pending B23": 438,
                "pending B24": 294,
                "prepend": 662,
                "reads as continuation": 599,
                "reads as diagnostic": 775,
                "reads as entry": 754,
                "reads as ignored": 876,
                "reads as other warning": 378,
                "reads as skipped": 872,
                "reads as unparsed timing": 596,
                "reads as unstated": 315,
                "recorded": 414,
                "surplus": 408,
                "truncated escape": 328,
                "unknown place": 209,
                "unterminated": 303
            ]
        )
        #expect(counts.longest <= BuildOutputInterpreter.lineCap)
    }
}
