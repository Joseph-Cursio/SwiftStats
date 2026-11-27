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
        "CRLF": 889,
        "a bar in a message line": 648,
        "a blank line not of spaces ending a message before a plain line": 471,
        "a footnote ending a message with no ID": 284,
        "a function body's times to sum": 258,
        "a macro diagnostic before a near-miss origin": 208,
        "a macro diagnostic before a padded origin": 107,
        "a message line ending in white space": 333,
        "a message taking a line ending in > not led by [#": 169,
        "a message taking a line led by [# alone": 136,
        "a message taking a line led by [# and ending in >": 136,
        "a message taking a line led by [# and holding ]: < with no closing >": 135,
        "a message taking a line led by other digits and a bar": 333,
        "a message with no ID taking a line": 556,
        "a refused timing line right after a message's line": 9,
        "an empty line ending a message before a plain line": 197,
        "at the line cap": 23,
        "crosses the continuation limit": 127,
        "decoy place": 81,
        "diagnostic in the log": 821,
        "diagnostic repeated across files": 149,
        "diagnostic repeated within a file": 2,
        "empty declaration": 278,
        "empty message": 121,
        "empty standard error": 100,
        "escaped": 802,
        "fully stated": 801,
        "inner suffix": 223,
        "inserted blank": 305,
        "invalid UTF-8": 35,
        "lone CR": 756,
        "macro origin": 399,
        "near header": 411,
        "near origin": 284,
        "no suffix": 899,
        "padded origin": 155,
        "prepend": 507,
        "reads as continuation": 705,
        "reads as diagnostic": 944,
        "reads as entry": 674,
        "reads as ignored": 914,
        "reads as other warning": 238,
        "reads as skipped": 938,
        "reads as unparsed timing": 459,
        "reads as unstated": 199,
        "recorded": 278,
        "surplus": 301,
        "truncated escape": 297,
        "unknown place": 402,
        "unterminated": 309
    ]

    /// What `counts(.decided)` draws: the rules every property draws.
    static let decidedCounts: [String: Int] = [
        "B10 shape": 249,
        "B23 shape": 534,
        "B24 shape": 180,
        "CRLF": 885,
        "a bar in a message line": 676,
        "a blank line not of spaces ending a message before a plain line": 427,
        "a footnote ending a message with no ID": 261,
        "a function body's times to sum": 256,
        "a macro diagnostic before a near-miss origin": 201,
        "a macro diagnostic before a padded origin": 107,
        "a message line ending in white space": 311,
        "a message taking a line ending in > not led by [#": 140,
        "a message taking a line led by [# alone": 131,
        "a message taking a line led by [# and ending in >": 132,
        "a message taking a line led by [# and holding ]: < with no closing >": 146,
        "a message taking a line led by other digits and a bar": 386,
        "a message with no ID taking a line": 620,
        "a refused timing line right after a message's line": 208,
        "an empty line ending a message before a plain line": 209,
        "at the line cap": 20,
        "crosses the continuation limit": 92,
        "decoy place": 82,
        "diagnostic in the log": 820,
        "diagnostic repeated across files": 159,
        "diagnostic repeated within a file": 1,
        "empty declaration": 299,
        "empty message": 89,
        "empty standard error": 84,
        "escaped": 806,
        "fully stated": 791,
        "inner suffix": 203,
        "inserted blank": 167,
        "invalid UTF-8": 38,
        "lone CR": 743,
        "macro origin": 364,
        "near header": 345,
        "near origin": 264,
        "no suffix": 914,
        "padded origin": 150,
        "prepend": 728,
        "reads as continuation": 728,
        "reads as diagnostic": 950,
        "reads as entry": 719,
        "reads as ignored": 914,
        "reads as other warning": 231,
        "reads as skipped": 913,
        "reads as unparsed timing": 568,
        "reads as unstated": 209,
        "recorded": 279,
        "surplus": 264,
        "truncated escape": 294,
        "unknown place": 420,
        "unterminated": 326
    ]

    /// The shapes counted when either file has them: P1.5's antecedents.
    static let fileShapes: [(label: String, holds: @Sendable ([GeneratedBuildLine]) -> Bool)] = [
        ("a message with no ID taking a line", BuildOutputGen.takesUnidentified),
        ("a blank line not of spaces ending a message before a plain line", BuildOutputGen.endsAtOtherBlank),
        ("a macro diagnostic before a near-miss origin", { BuildOutputGen.macroBefore(.nearOrigin, in: $0) }),
        ("a macro diagnostic before a padded origin", { BuildOutputGen.macroBefore(.paddedOrigin, in: $0) }),
        ("a bar in a message line", BuildOutputGen.barInMessage),
        ("a message taking a line led by other digits and a bar", BuildOutputGen.takesNonASCIIGutter),
        ("a message line ending in white space", BuildOutputGen.endsInWhiteSpace),
        (BuildOutputPBT.emptyLine, BuildOutputGen.endsAtEmptyLine),
        (BuildOutputPBT.footnoteEnd, BuildOutputGen.endsAtFootnote)
    ] + BuildOutputGen.NearFootnote.allCases.map { form in
        (form.label, { BuildOutputGen.takesNearFootnote(form, in: $0) })
    }

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
                "a line feed made CRLF": 979,
                "a synthesized entry": 213,
                "an entry on a record": 403,
                "an entry on a type or the file": 480
            ]
        )
    }
}
