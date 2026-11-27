import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of reading the T1 build's output (M7 design §6.1, the
/// doc comments of `BuildOutputReader` and `BuildLineGrammar`), over
/// generated output whose every line is labelled with what it reads as
/// (`BuildOutputGen`, under the rules U10 and U13 decided, which the
/// reader follows since step 7's fixes, B10, B23 and B24): reading any
/// output never traps, every valid timing line becomes its entry, and the
/// entries map onto a measured package without trapping, every time
/// accounted for (P1.1, which guards B1 and B18); a time field reads as
/// its exact value when its whole part has at most twelve digits, and as
/// none otherwise (P1.3, `BuildOutputPBT+Hundredths`, with the walk over
/// edge numerals); every standard error line holding `ms<TAB>` is an entry
/// or counted, and no message takes one (P1.2), and every entry the grammar
/// states reads back from its line (P1.4, `BuildOutputPBT+Timing`); a
/// diagnostic reads as written (P1.5, `+Diagnostics`); escapes written
/// into lines change nothing but the escaped count (P1.6, `+Escapes`), and
/// CRLF line breaks nothing (P1.7, `+LineBreaks`); the standard error read
/// in two halves reads as a whole, and a timing line moved into the log
/// leaves only its entry out (P1.8, `+Split`). `BuildOutputReaderTests`
/// holds the fixed examples; each property here has its own, calling its
/// shared check, and meta-tests that feed a planted defect's output to
/// that check.
@Suite("Build output reader: properties", .tags(.pbt))
struct BuildOutputPBT {
    /// P1.1's base runs: the engine's default.
    static let readingRuns = 100
    /// What P1.1's tally counts when the standard error holds a timing line
    /// valid but for its empty declaration, which must read as no entry
    /// (design D14: the generator's meta-test counts it in more than 0.3 of
    /// outputs, so 100 runs never miss it).
    static let emptyDeclaration = "an empty-declaration timing line"
    /// What P1.1's tally counts when two of the moved function bodies share
    /// a place, so the mapper sums their times (design D14: the generator's
    /// meta-test counts it in more than 0.3 of outputs).
    static let summedBodies = "two function bodies' times to sum"
    /// The antecedents P1.1 must reach at least once each.
    static let readingAntecedents = placements + [emptyDeclaration, summedBodies]

    /// P1.1's regressions: B1's line, a time past what an `Int` holds,
    /// after a warning and before the largest time the bound allows.
    static let overlongEntries = [
        CorpusEntry(
            input: [
                BuildLineDraft(
                    .header(
                        location: .file(BuildPlace(path: "/p/a.swift", line: 1, column: 2)),
                        severity: .warning,
                        message: SuffixedText("w")
                    ),
                    text: "/p/a.swift:1:2: warning: w",
                    traits: []
                ),
                BuildLineDraft(.overlongTiming, text: "92233720368547759ms\t<invalid loc>", traits: []),
                timing("999999999999.99", hundredths: 99_999_999_999_999, place: nil)
            ],
            pins: "B1: an overlong time trapped the collector"
        )
    ]

    /// Whether `sample`'s standard error read as `read`, and its entries
    /// mapped as P1.1 states: every valid timing line read as its entry,
    /// in order, and nothing else as one; and both mappings, the entries
    /// as read (`asRead`, the recordings' root token standing for the
    /// package's root) and moved into the package's file (`onFixture`),
    /// hold the mapping laws. Records an issue for each law that fails.
    static func checkReading(
        _ sample: GeneratedBuildOutput,
        read: BuildOutput,
        asRead: MappedEntries,
        onFixture: MappedEntries
    ) -> Bool {
        [
            holds(
                [(read.entries == sample.entries, "reads every valid timing line as its entry, and nothing else")],
                subject: "reading \(read.entries.count) entries"
            ),
            checkMapping(asRead, subject: "the entries as read"),
            checkMapping(onFixture, subject: "the entries moved into the package"),
            checkPlaced(onFixture, subject: "the entries moved into the package")
        ]
        .allSatisfy(\.self)
    }

    /// `sample` read, and its entries mapped by `library`'s mapper as read
    /// and moved into its file, checked by `checkReading`.
    static func check(_ sample: GeneratedBuildOutput, library: TimingFigureTests.Library) -> Bool {
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let rooted = rooted(read.entries, at: library.root)
        let moved = moved(read.entries, into: library.root)
        return checkReading(
            sample,
            read: read,
            asRead: MappedEntries(entries: rooted, mapped: library.mapper.map(rooted)),
            onFixture: MappedEntries(entries: moved, mapped: library.mapper.map(moved))
        )
    }

    /// Records an issue naming `subject` for each law in `laws` that
    /// fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record("\(subject) fails: it \(law.law)")
        }
        return laws.allSatisfy(\.holds)
    }

    /// The output whose standard error is `stderr` and whose task log is
    /// `log`, each line written plain and ended with a line break, and
    /// labelled under the decided rules.
    static func output(_ stderr: [BuildLineDraft], log: [BuildLineDraft]) -> GeneratedBuildOutput {
        GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(blocks: stderr.map { [$0] }, decorations: [], terminated: true),
            log: BuildFileDraft(blocks: log.map { [$0] }, decorations: [], terminated: true)
        )
    }

    /// `read` with `entries` in place of its own: what a planted defect in
    /// the reader would return.
    static func output(_ read: BuildOutput, entries: [TimingEntry]) -> BuildOutput {
        BuildOutput(
            entries: entries,
            diagnostics: read.diagnostics,
            escapedLines: read.escapedLines,
            unparsedTimingLines: read.unparsedTimingLines,
            otherWarningLines: read.otherWarningLines
        )
    }

    /// A valid timing line of a function body: `time` (as written, without
    /// its unit) taking `hundredths`, at `place`, or `<invalid loc>`.
    static func timing(_ time: String, hundredths: Int, place: BuildPlace?) -> BuildLineDraft {
        let declaration = "global function f()"
        let entry = TimingEntry(kind: .function, hundredths: hundredths, place: place, declaration: declaration)
        let location = place.map { "\($0.path):\($0.line):\($0.column)" } ?? BuildOutputGen.invalidLocation
        return BuildLineDraft(.timing(entry), text: "\(time)ms\t\(location)\t\(declaration)", traits: [])
    }

    // MARK: P1.1

    /// Invariant: reading any build output terminates without trapping,
    /// every valid timing line becomes its entry (in order, and nothing
    /// else does), and mapping the entries never traps and accounts for
    /// every time.
    /// Why it holds: `BuildOutputReader`'s doc comments (the standard
    /// error's timing lines are its entries, in order; a timing line ends
    /// any message, so none is consumed by one) and `BuildLineGrammar`'s
    /// (a time has at most twelve whole digits, B1); `TimingMapper`'s
    /// header (synthesized entries left out and counted, a sum rounded
    /// once, half up; the totals add the function-body entries on records
    /// not nested in a body, on types and on files; sums stop at `Int.max`
    /// rather than trapping, B18).
    /// Why it might not: the generator draws the decided rules' shapes (U10,
    /// U13), B10's, B23's and B24's among them: a Prepend scalar just
    /// before a timing place's colon stays in the path since B23's fix
    /// (step 7c), so such a line is an entry. Diagnostics, the unparsed count
    /// and escapes are P1.2, P1.5 and P1.6's. Times stay within twelve
    /// digits and files within 40 lines, so no sum nears `Int.max`: B18's
    /// trap is guarded by the bound, and `TimingFigureTests+Saturation`
    /// pins the saturation itself. B1's other half, an overlong time
    /// ending a message and counted unparsed (as every refused timing line
    /// does since B10's fix), is a diagnostics law, so here only the B1
    /// example states it. The moved entries must reach a record, a type or
    /// the file, and none; two of them must be function bodies at one
    /// place, whose times the mapper sums; and the standard error must
    /// hold a timing line valid but for its empty declaration: each in
    /// some run (the tally). The generator draws the last two as blocks of
    /// their own so that they do.
    /// Oracle: the generator's labels (each line's reading, known by
    /// construction), and sums worked out apart from the mapper; planted
    /// defects: B1's bound removed, an empty declaration accepted, a
    /// synthesized entry's time not counted, and a function's entries
    /// kept as their largest rather than summed, and a place split on
    /// Characters (B23's fix undone), each detected in 20 of 20
    /// calibration runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "reading any build output never traps, every valid timing line becomes its entry, and the entries map",
        .timeLimit(PBTBudget.timeLimit)
    )
    func readingIsTotal() async throws {
        guard let library = try Self.library() else {
            return
        }
        defer { library.package.remove() }
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.readingRuns), input: BuildOutputGen.output(.decided)) { sample in
            PBTTrace.note(sample)
            let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
            let rooted = Self.rooted(read.entries, at: library.root)
            let moved = Self.moved(read.entries, into: library.root)
            let onFixture = library.mapper.map(moved)
            Self.tally(onFixture, in: tally)
            if sample.traits.contains(.emptyDeclaration) {
                tally.fire(Self.emptyDeclaration)
            }
            if BuildOutputGen.repeatsBody(moved) {
                tally.fire(Self.summedBodies)
            }
            let passed = Self.checkReading(
                sample,
                read: read,
                asRead: MappedEntries(entries: rooted, mapped: library.mapper.map(rooted)),
                onFixture: MappedEntries(entries: moved, mapped: onFixture)
            )
            if passed == false {
                PBTTrace.firstFailure(sample, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.readingAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("the recorded timing lines read as their entries, and map with every time accounted for")
    func recordedTimings() throws {
        guard let library = try Self.library() else {
            return
        }
        defer { library.package.remove() }
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(blocks: BuildOutputGen.recordedTimings, decorations: [], terminated: true),
            log: BuildFileDraft(blocks: [BuildOutputGen.recordedGroups[0]], decorations: [], terminated: true)
        )

        #expect(Self.check(sample, library: library))
        #expect(sample.entries.count == BuildOutputGen.recordedTimings.count)
    }

    @Test(
        "B1: a time past what an Int holds ends a warning's message and is no entry; the time after it is one",
        arguments: overlongEntries
    )
    func overlongTime(entry: CorpusEntry<[BuildLineDraft]>) throws {
        guard let library = try Self.library() else {
            return
        }
        defer { library.package.remove() }
        let sample = Self.output(entry.input, log: [])
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(Self.check(sample, library: library))
        #expect(sample.entries.map(\.hundredths) == [99_999_999_999_999])
        #expect(read.diagnostics.map(\.message) == ["w"])
        #expect(read.unparsedTimingLines == 1)
        #expect(read == sample.expected)
    }

    @Test("B18: forty of the largest times the bound allows, on one function, total exactly")
    func largestTimes() throws {
        guard let library = try Self.library() else {
            return
        }
        defer { library.package.remove() }
        let place = BuildPlace(path: BuildOutputGen.recordedRoot + "/" + Self.libraryFile, line: 1, column: 13)
        let line = Self.timing("999999999999.99", hundredths: 99_999_999_999_999, place: place)
        let sample = Self.output(Array(repeating: line, count: BuildOutputInterpreter.lineCap), log: [])
        let mapped = library.mapper.map(Self.rooted(sample.entries, at: library.root))

        #expect(Self.check(sample, library: library))
        #expect(mapped.records.map(\.key) == ["Lib::func first() -> Int"])
        // 40 × 99999999999999 hundredths is 39999999999999.60 ms.
        #expect(mapped.records.map(\.milliseconds) == [40_000_000_000_000])
        #expect(mapped.totals.milliseconds == 40_000_000_000_000)
    }

    @Test("a planted defect's reading or mapping fails P1.1's laws")
    func readingDefectsDetected() throws {
        guard let library = try Self.library() else {
            return
        }
        defer { library.package.remove() }
        let overlong = BuildLineDraft(.overlongTiming, text: "1000000000000ms\t<invalid loc>", traits: [])
        let synthesized = Self.timing("1.50", hundredths: 150, place: nil)
        let undeclared = BuildLineDraft(.malformedTiming, text: "2.00ms\t/p/a.swift:1:2\t", traits: [])
        let sample = Self.output([overlong, synthesized, undeclared], log: [])
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let given = MappedEntries(entries: read.entries, mapped: library.mapper.map(read.entries))
        let overlongEntry = TimingEntry(kind: .function, hundredths: 100_000_000_000_000, place: nil, declaration: nil)
        let undeclaredPlace = BuildPlace(path: "/p/a.swift", line: 1, column: 2)
        let undeclaredEntry = TimingEntry(kind: .function, hundredths: 200, place: undeclaredPlace, declaration: "")
        let unbounded = Self.output(read, entries: [overlongEntry] + read.entries)
        let declarationless = Self.output(read, entries: read.entries + [undeclaredEntry])
        let untimed = TimingMapper.Mapped(
            records: given.mapped.records,
            attachments: given.mapped.attachments,
            unmapped: BuildUnmapped(
                synthesized: BuildEntryCount(entries: 1, milliseconds: 0),
                macro: given.mapped.unmapped.macro
            ),
            dropped: given.mapped.dropped,
            totals: given.mapped.totals,
            counted: given.mapped.counted
        )

        PlantedDefect.expectCaught("B1's bound removed: an overlong time read", sourceLocation: #_sourceLocation) {
            Self.checkReading(sample, read: unbounded, asRead: given, onFixture: given)
        }
        PlantedDefect.expectCaught("an empty declaration read as an entry", sourceLocation: #_sourceLocation) {
            Self.checkReading(sample, read: declarationless, asRead: given, onFixture: given)
        }
        PlantedDefect.expectCaught("a synthesized entry's time not counted", sourceLocation: #_sourceLocation) {
            Self.checkReading(
                sample,
                read: read,
                asRead: MappedEntries(entries: read.entries, mapped: untimed),
                onFixture: given
            )
        }
    }
}
