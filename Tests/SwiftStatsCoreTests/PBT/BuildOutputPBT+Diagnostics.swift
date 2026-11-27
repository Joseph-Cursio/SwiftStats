//
//  BuildOutputPBT+Diagnostics.swift
//  SwiftStatsCoreTests
//
//  P1.5: a diagnostic's header and the lines that can only continue it
//  read as one diagnostic with the place, severity, message, ID and group
//  the generator wrote, the place being the first prefix before
//  `: <severity>: ` that reads as one; a message takes its lines up to the
//  last that ends with an ID or a group (M7 C2), at most 20, and all of
//  them when none does (design B8, decided U10: Swift's reading); a macro
//  diagnostic's origin is the note right after them; the two files'
//  diagnostics are kept once each.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P1.5.
extension BuildOutputPBT {
    /// P1.5's base runs, over the engine's 100: its rarest antecedent, a
    /// macro diagnostic whose origin note is read, comes in 78 of 1,000
    /// outputs (the generator's meta-test), and design D14 needs
    /// `n >= ln(10^-6) / ln(1 - 0.078)`, about 171, for a random run to
    /// miss it with probability below 10^-6.
    static let diagnosticRuns = 180
    /// What P1.5's tally counts when a diagnostic is read.
    static let readDiagnostic = "a diagnostic"
    /// What P1.5's tally counts when a message with no ID or group takes a
    /// line (U10).
    static let unidentifiedRun = "a message with no ID taking a line"
    /// What P1.5's tally counts when a message takes a line ending in a
    /// suffix before the line that ends it (M7 C2).
    static let innerSuffix = "a suffix inside a message"
    /// What P1.5's tally counts when a message's lines run past the limit.
    static let pastLimit = "a run past the limit"
    /// What P1.5's tally counts when a header's place is a decoy's.
    static let decoy = "a decoy place"
    /// What P1.5's tally counts when a macro diagnostic's origin is read.
    static let origin = "an origin note read"
    /// The antecedents P1.5 must reach at least once each.
    static let diagnosticAntecedents = [readDiagnostic, unidentifiedRun, innerSuffix, pastLimit, decoy, origin]

    /// The diagnostics `sample`'s labels state, standard error first, each
    /// kept once, as the reader's doc comment states.
    static func labelledDiagnostics(_ sample: GeneratedBuildOutput) -> [BuildDiagnostic] {
        keptOnce(
            sample.lines.compactMap { line in
                if case .diagnostic(let diagnostic) = line.reading {
                    return diagnostic
                }
                return nil
            }
        )
    }

    /// `diagnostics` with each kept once, where it first comes.
    static func keptOnce(_ diagnostics: [BuildDiagnostic]) -> [BuildDiagnostic] {
        var seen = Set<BuildDiagnostic>()
        return diagnostics.filter { seen.insert($0).inserted }
    }

    /// Whether `part` is `whole` with some elements left out, in order.
    static func isSubsequence(_ part: [BuildDiagnostic], of whole: [BuildDiagnostic]) -> Bool {
        var rest = whole[...]
        for element in part {
            guard let found = rest.firstIndex(of: element) else {
                return false
            }
            rest = rest[rest.index(after: found)...]
        }
        return true
    }

    /// The first diagnostic where `read` and `expected` differ, in ASCII,
    /// for a failure's report.
    static func firstDifference(_ read: [BuildDiagnostic], _ expected: [BuildDiagnostic]) -> String {
        let shared = min(read.count, expected.count)
        let index = (0..<shared).first { read[$0] != expected[$0] } ?? shared
        let readText = read.indices.contains(index) ? "\(read[index])" : "none"
        let expectedText = expected.indices.contains(index) ? "\(expected[index])" : "none"
        return PBTTrace.ascii("at \(index), read \(readText), expected \(expectedText)")
    }

    /// Whether `sample`'s files read as `read` as P1.5 states: when every
    /// line's reading is stated, the labelled diagnostics and other
    /// warnings exactly; otherwise (a wild line, which may read as
    /// anything) the labelled diagnostics among those read, in order.
    /// Records an issue for each law that fails.
    static func checkDiagnostics(_ sample: GeneratedBuildOutput, read: BuildOutput) -> Bool {
        let labelled = labelledDiagnostics(sample)
        guard let expected = sample.expected else {
            return holds(
                [
                    (
                        isSubsequence(labelled, of: read.diagnostics),
                        "reads the \(labelled.count) labelled diagnostics in order among its \(read.diagnostics.count)"
                    )
                ],
                subject: "reading a file with a wild line"
            )
        }
        return holds(
            [
                (
                    read.diagnostics == expected.diagnostics,
                    "reads the \(expected.diagnostics.count) labelled diagnostics "
                        + "(\(firstDifference(read.diagnostics, expected.diagnostics)))"
                ),
                (
                    read.otherWarningLines == expected.otherWarningLines,
                    "counts \(expected.otherWarningLines) other warning lines (counted \(read.otherWarningLines))"
                )
            ],
            subject: "reading \(expected.diagnostics.count) diagnostics"
        )
    }

    /// Fires `tally`'s labels for what `sample` holds.
    static func tallyDiagnostics(_ sample: GeneratedBuildOutput, in tally: AntecedentTally) {
        let traits = sample.traits
        let fired = [
            (labelledDiagnostics(sample).isEmpty == false, readDiagnostic),
            ([sample.stderrLines, sample.logLines].contains(where: BuildOutputGen.takesUnidentified), unidentifiedRun),
            (traits.contains(.innerSuffix), innerSuffix),
            (traits.contains(.crossesLimit), pastLimit),
            (traits.contains(.decoyPlace), decoy),
            (traits.contains(.macroOrigin), origin)
        ]
        for (didFire, label) in fired where didFire {
            tally.fire(label)
        }
    }

    // MARK: P1.5

    /// Invariant: a diagnostic's header followed by lines that can only
    /// continue it reads as one diagnostic with the place, severity,
    /// message, ID and group written, its place the first prefix before
    /// `: <severity>: ` that reads as one, and both files' diagnostics are
    /// kept once each, standard error first.
    /// Why it holds: `BuildOutputReader`'s header (a message takes the lines
    /// after it that can't be anything else, at most 20, up to the last
    /// after which the joined text ends with an ID or a group, all of them
    /// when none does; a macro diagnostic's place is the origin note after
    /// its message; diagnostics kept once each), `BuildLineGrammar`'s (the
    /// first-match rule) and `DiagnosticText`'s (suffixes read from the
    /// end); design B8, decided U10 (a message with no ID takes its lines,
    /// Swift's reading, which the checker adopted in step 7b).
    /// Why it might not: a wild line may read as anything, so with one
    /// present only the labelled diagnostics are required, in order; words
    /// can't spell a severity, so a header is only where a block wrote one.
    /// The run of 180 is sized for the rarest antecedent (the tally).
    /// Oracle: the generator's labels (each diagnostic known by
    /// construction from the interpreter's statement of these rules);
    /// planted defects: the first completing line taken rather than the
    /// last (C2), a message with no ID taking no line (the checker's old
    /// B8 rule), the last matching place taken rather than the first, the
    /// origin note never read, and the limit one line longer, each
    /// detected in 20 of 20 calibration runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "a diagnostic's header and the lines that only continue it read as one diagnostic with what was written",
        .timeLimit(PBTBudget.timeLimit)
    )
    func diagnosticsReadAsWritten() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        let input = BuildOutputGen.output(.decided)
        await propertyCheck(count: PBTBudget.runs(Self.diagnosticRuns), input: input) { sample in
            PBTTrace.note(sample)
            Self.tallyDiagnostics(sample, in: tally)
            let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
            if Self.checkDiagnostics(sample, read: read) == false {
                PBTTrace.firstFailure(sample, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.diagnosticAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("the recorded diagnostics read as recorded, in either file, each kept once")
    func recordedDiagnostics() {
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(blocks: BuildOutputGen.recordedGroups, decorations: [], terminated: true),
            log: BuildFileDraft(blocks: BuildOutputGen.recordedGroups.reversed(), decorations: [], terminated: false)
        )
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(Self.checkDiagnostics(sample, read: read))
        #expect(read.diagnostics.map(\.identifier) == ["pound_warning", "no_throw_in_try", "bridged_warning"])
    }

    /// The decided-rules generator draws no diagnostic twice within one
    /// file (its meta-test), so P1.5's random runs leave this case to this
    /// example: a reader keeping diagnostics once only across the two files
    /// would pass them.
    @Test("the recorded diagnostics printed twice in the standard error are each kept once")
    func repeatedDiagnosticsKeptOnce() {
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(
                blocks: BuildOutputGen.recordedGroups + BuildOutputGen.recordedGroups,
                decorations: [],
                terminated: true
            ),
            log: BuildFileDraft(blocks: [], decorations: [], terminated: true)
        )
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(Self.checkDiagnostics(sample, read: read))
        #expect(read.diagnostics.map(\.identifier) == ["pound_warning", "no_throw_in_try", "bridged_warning"])
    }

    @Test("""
        a recorded error with no ID takes the failed frontend command printed after it (design B8, decided U10), \
        escapes stripped, paths replaced and the command shortened
        """)
    func recordedUnidentifiedError() {
        let command = "/Toolchain/usr/bin/swift-frontend -frontend -c "
            + "/work/Pkg/Sources/RealModule/AlgebraicField.swift -module-name RealModule"
        let message = SuffixedText("index output filenames do not match input source files")
        let sample = Self.output(
            [
                BuildLineDraft(
                    .header(location: .unknown(line: 0), severity: .error, message: message),
                    text: "<unknown>:0: error: " + message.rendered,
                    traits: []
                ),
                BuildOutputGen.recordedPlain("Failed frontend command:"),
                BuildOutputGen.recordedPlain(command),
                BuildLineDraft(
                    .stopper,
                    text: "info: SwiftCompile normal arm64 Compiling\\ AlgebraicField.swift",
                    traits: []
                ),
                BuildLineDraft(.stopper, text: "error: Build failed", traits: [])
            ],
            log: []
        )
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(Self.checkDiagnostics(sample, read: read))
        #expect(read.diagnostics.map(\.message) == [message.body + "\nFailed frontend command:\n" + command])
    }

    @Test("a decoy place before the real one is the place, by the first-match rule, and the rest is the message")
    func decoyPlaceRead() {
        let place = BuildOutputGen.FilePlace(
            text: "/q/b.swift:3:4",
            place: BuildPlace(path: "/q/b.swift", line: 3, column: 4),
            traits: []
        )
        let foremost = BuildOutputGen.FilePlace(
            text: "/p/a.swift:1:2",
            place: BuildPlace(path: "/p/a.swift", line: 1, column: 2),
            traits: []
        )
        let header = BuildOutputGen.headerLine(
            place: BuildOutputGen.HeaderPlace(text: place.text, location: .file(place.place), traits: []),
            severity: .error,
            message: SuffixedText(body: "x", identifier: .valid("no_throw_in_try"), group: .absent),
            decoy: (foremost, .warning)
        )
        let sample = Self.output([header], log: [])
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(Self.checkDiagnostics(sample, read: read))
        #expect(read.diagnostics.map(\.location) == [.file(foremost.place)])
        #expect(read.diagnostics.map(\.message) == ["/q/b.swift:3:4: error: x"])
    }

    @Test("a planted defect's reading fails P1.5's laws")
    func diagnosticDefectsDetected() {
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(blocks: BuildOutputGen.recordedGroups, decorations: [], terminated: true),
            log: BuildFileDraft(blocks: [], decorations: [], terminated: true)
        )
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let noOrigin = read.diagnostics.map { diagnostic in
            BuildDiagnostic(
                severity: diagnostic.severity,
                location: diagnostic.location,
                message: diagnostic.message,
                identifier: diagnostic.identifier,
                group: diagnostic.group,
                origin: nil
            )
        }
        let firstLineOnly = read.diagnostics.map { diagnostic in
            BuildDiagnostic(
                severity: diagnostic.severity,
                location: diagnostic.location,
                message: String(diagnostic.message.prefix { $0 != "\n" }),
                identifier: diagnostic.identifier,
                group: diagnostic.group,
                origin: diagnostic.origin
            )
        }
        func with(_ diagnostics: [BuildDiagnostic]) -> BuildOutput {
            BuildOutput(
                entries: read.entries,
                diagnostics: diagnostics,
                escapedLines: read.escapedLines,
                unparsedTimingLines: read.unparsedTimingLines,
                otherWarningLines: read.otherWarningLines
            )
        }

        PlantedDefect.expectDetected("the origin note never read", sourceLocation: #_sourceLocation) {
            Self.checkDiagnostics(sample, read: with(noOrigin))
        }
        PlantedDefect.expectDetected("a message taking no line after its header", sourceLocation: #_sourceLocation) {
            Self.checkDiagnostics(sample, read: with(firstLineOnly))
        }
        PlantedDefect.expectDetected("a diagnostic kept twice", sourceLocation: #_sourceLocation) {
            Self.checkDiagnostics(sample, read: with(read.diagnostics + read.diagnostics.prefix(1)))
        }
    }
}
