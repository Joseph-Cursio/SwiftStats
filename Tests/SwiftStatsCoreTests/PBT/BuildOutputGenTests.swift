import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the build-output generator draws (design D14): from a fixed seed,
/// a thousand outputs reach each shape a build-output property reads, and
/// each antecedent it conditions on, an exact number of times, counted per
/// output (a property's chance per run). The rules from before step 7's
/// fixes (`current`, which no property draws since step 7c) never draw
/// B10's, B23's or B24's shapes; the decided rules, which every property
/// draws, draw each. No line ends in a carriage return, so CRLF goes only
/// where the reader drops just the CR, and no file passes the line cap.
/// The counts hold under this engine's generator code and this standard
/// library; a change to either redraws them.
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

    /// What `counts(.current)` draws: the rules from before step 7's fixes.
    static let currentCounts: [String: Int] = [
        "CRLF": 893,
        "a bar in a message line": 607,
        "a blank line not of spaces ending a message before a plain line": 532,
        "a function body's times to sum": 288,
        "a macro diagnostic before a near-miss origin": 257,
        "a macro diagnostic before a padded origin": 131,
        "a message line ending in white space": 393,
        "a message taking a line led by other digits and a bar": 386,
        "a message with no ID taking a line": 248,
        "a refused timing line right after a message's line": 2,
        "at the line cap": 35,
        "crosses the continuation limit": 140,
        "decoy place": 90,
        "diagnostic in the log": 784,
        "diagnostic repeated across files": 155,
        "diagnostic repeated within a file": 1,
        "empty declaration": 328,
        "empty message": 118,
        "empty standard error": 90,
        "escaped": 811,
        "fully stated": 785,
        "inner suffix": 264,
        "inserted blank": 289,
        "invalid UTF-8": 43,
        "lone CR": 747,
        "macro origin": 443,
        "near header": 457,
        "near origin": 327,
        "no suffix": 789,
        "padded origin": 164,
        "prepend": 518,
        "reads as continuation": 556,
        "reads as diagnostic": 917,
        "reads as entry": 709,
        "reads as ignored": 906,
        "reads as other warning": 270,
        "reads as skipped": 948,
        "reads as unparsed timing": 510,
        "reads as unstated": 215,
        "recorded": 330,
        "surplus": 330,
        "truncated escape": 280,
        "unknown place": 267,
        "unterminated": 320
    ]

    /// What `counts(.decided)` draws: the rules every property draws.
    static let decidedCounts: [String: Int] = [
        "B10 shape": 257,
        "B23 shape": 539,
        "B24 shape": 203,
        "CRLF": 877,
        "a bar in a message line": 658,
        "a blank line not of spaces ending a message before a plain line": 499,
        "a function body's times to sum": 269,
        "a macro diagnostic before a near-miss origin": 242,
        "a macro diagnostic before a padded origin": 117,
        "a message line ending in white space": 323,
        "a message taking a line led by other digits and a bar": 415,
        "a message with no ID taking a line": 433,
        "a refused timing line right after a message's line": 220,
        "at the line cap": 33,
        "crosses the continuation limit": 118,
        "decoy place": 88,
        "diagnostic in the log": 790,
        "diagnostic repeated across files": 126,
        "diagnostic repeated within a file": 2,
        "empty declaration": 330,
        "empty message": 122,
        "empty standard error": 82,
        "escaped": 824,
        "fully stated": 741,
        "inner suffix": 234,
        "inserted blank": 214,
        "invalid UTF-8": 50,
        "lone CR": 728,
        "macro origin": 402,
        "near header": 421,
        "near origin": 311,
        "no suffix": 831,
        "padded origin": 159,
        "prepend": 732,
        "reads as continuation": 639,
        "reads as diagnostic": 922,
        "reads as entry": 734,
        "reads as ignored": 896,
        "reads as other warning": 239,
        "reads as skipped": 912,
        "reads as unparsed timing": 610,
        "reads as unstated": 259,
        "recorded": 320,
        "surplus": 284,
        "truncated escape": 308,
        "unknown place": 322,
        "unterminated": 294
    ]

    /// The shapes counted when either file has them: P1.5's antecedents.
    static let fileShapes: [(label: String, holds: @Sendable ([GeneratedBuildLine]) -> Bool)] = [
        ("a message with no ID taking a line", BuildOutputGen.takesUnidentified),
        ("a blank line not of spaces ending a message before a plain line", BuildOutputGen.endsAtOtherBlank),
        ("a macro diagnostic before a near-miss origin", { BuildOutputGen.macroBefore(.nearOrigin, in: $0) }),
        ("a macro diagnostic before a padded origin", { BuildOutputGen.macroBefore(.paddedOrigin, in: $0) }),
        ("a bar in a message line", BuildOutputGen.barInMessage),
        ("a message taking a line led by other digits and a bar", BuildOutputGen.takesNonASCIIGutter),
        ("a message line ending in white space", BuildOutputGen.endsInWhiteSpace)
    ]

    /// What `output` has: each trait any line has, each kind of reading,
    /// and whether its diagnostics are stated, one is in both files (the
    /// reader keeps it once), one repeats within a file, two function
    /// bodies at one place have times to sum, a refused timing line comes
    /// right after a header or a line its message took (P1.2's antecedent),
    /// a message with no ID takes a line, a blank line that isn't spaces
    /// ends a message before a plain line, a macro diagnostic comes before
    /// a near-miss or a padded origin note, a message line holds a bar or
    /// ends in white space, and a message takes a line led by other digits
    /// and a bar (P1.5's), a file is empty or at
    /// the line cap, and a line ends in a carriage return (never
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
        if BuildOutputGen.refusesInMessage(output.stderrLines) {
            shapes.append("a refused timing line right after a message's line")
        }
        let files = [output.stderrLines, output.logLines]
        shapes += fileShapes.filter { files.contains(where: $0.holds) }.map(\.label)
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

    /// How often, over `draws` outputs under the decided rules starting
    /// from `seeded`, the entries P1.1 moves into its package reach each
    /// placement it requires (`BuildOutputPBT.placements`), and a line P1.7
    /// ends with CRLF ended with a line feed (`lineFeedChanged`): the
    /// antecedents those properties count per run.
    static func readingCounts(library: TimingFigureTests.Library) throws -> [String: Int] {
        var random = seeded
        let tally = AntecedentTally()
        let generator = BuildOutputGen.output(.decided)
        for _ in 0..<draws {
            let output = try generator.run(using: &random, limit: attempts)
            let read = BuildOutputReader.read(stderr: output.stderr, log: output.log)
            BuildOutputPBT.tally(library.mapper.map(BuildOutputPBT.moved(read.entries, into: library.root)), in: tally)
            if output.lines.contains(where: { $0.lineBreak == "\n" }) {
                tally.fire(BuildOutputPBT.lineFeedChanged)
            }
        }
        return Dictionary(
            uniqueKeysWithValues: (BuildOutputPBT.placements + [BuildOutputPBT.lineFeedChanged]).map { label in
                (label, tally.count(label))
            }
        )
    }

    @Test("the rules from before step 7's fixes draw none of B10's, B23's or B24's shapes")
    func currentRules() throws {
        let counts = try Self.counts(.current)

        #expect(counts.labels == Self.currentCounts)
        #expect(counts.longest <= BuildOutputInterpreter.lineCap)
    }

    @Test("the decided rules reach every shape a property reads, B10's, B23's and B24's among them")
    func decidedRules() throws {
        let counts = try Self.counts(.decided)

        #expect(counts.labels == Self.decidedCounts)
        #expect(counts.longest <= BuildOutputInterpreter.lineCap)
    }

    @Test("the decided rules' outputs reach each placement P1.1 requires and a line feed P1.7 changes")
    func readingAntecedents() throws {
        guard let library = try BuildOutputPBT.library() else {
            return
        }
        defer { library.package.remove() }
        let counts = try Self.readingCounts(library: library)

        #expect(
            counts == [
                "a line feed made CRLF": 981,
                "a synthesized entry": 230,
                "an entry on a record": 423,
                "an entry on a type or the file": 521
            ]
        )
    }
}
