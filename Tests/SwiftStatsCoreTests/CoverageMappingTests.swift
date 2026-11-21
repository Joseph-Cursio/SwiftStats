@testable import SwiftStatsCore
import Testing

/// The coverage mapping on the Coverage fixture's recorded real export
/// (M5), checked against figures worked out by hand from its regions:
/// closures folded, regions of one range deduplicated, nested functions
/// apart from their parents, one-line sibling accessors each on their
/// line, overloads apart, a byte order mark's line, `main.swift`'s top-level
/// code, attachments, and null where coverage can't say.
@Suite("Coverage mapping")
struct CoverageMappingTests {
    /// A record's expected figures: lines and regions covered of total,
    /// the test targets that ran it, or the reason it has none.
    private struct Expected: Equatable, CustomStringConvertible {
        /// Lines covered and total.
        let lines: (Int, Int)?
        /// Regions covered and total.
        let regions: (Int, Int)?
        /// The test targets that ran it.
        let targets: [String]
        /// Why it has no data.
        let reason: String?

        var description: String {
            "lines \(String(describing: lines)), regions \(String(describing: regions)), \(targets), \(reason ?? "-")"
        }

        /// What `record` shows.
        init(_ record: CoverageRecord) {
            lines = record.lines.map { ($0.covered, $0.total) }
            regions = record.regions.map { ($0.covered, $0.total) }
            targets = record.testTargets
            reason = record.reason
        }

        /// Figures with data, run by `targets`.
        init(_ lines: (Int, Int), _ regions: (Int, Int), _ targets: [String]) {
            self.lines = lines
            self.regions = regions
            self.targets = targets
            reason = nil
        }

        /// No data, for `reason` (nil for a subscript container).
        init(reason: String?) {
            lines = nil
            regions = nil
            targets = []
            self.reason = reason
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.lines?.0 == rhs.lines?.0 && lhs.lines?.1 == rhs.lines?.1
                && lhs.regions?.0 == rhs.regions?.0 && lhs.regions?.1 == rhs.regions?.1
                && lhs.targets == rhs.targets && lhs.reason == rhs.reason
        }
    }

    /// The test target most of the fixture's tests are in.
    private static let probe = ["ProbeTests"]

    /// Every production record's figures, by key, worked out by hand.
    private static let expected: [String: Expected] = [
        // main.swift: the top-level entry's statement regions (lines 2, 8),
        // never run; its globals' regions go to the file.
        "Exe::<top-level code> @ Sources/Exe/main.swift": Expected((0, 2), (0, 2), []),
        "Exe::func exeHelper(_: Int) -> Int": Expected((3, 3), (1, 1), probe),
        "Probe::Box::init()": Expected((1, 1), (1, 1), probe),
        // A subscript with accessors is a container: no data, no reason.
        "Probe::Box::subscript(_: Int) -> Int": Expected(reason: nil),
        // One-line siblings: each accessor gets the line, with its count.
        "Probe::Box::subscript(_: Int) -> Int / { get }": Expected((1, 1), (1, 1), probe),
        "Probe::Box::subscript(_: Int) -> Int / { set }": Expected((0, 1), (0, 1), []),
        "Probe::Box::var both: Int { get }": Expected((1, 1), (1, 1), probe),
        "Probe::Box::var both: Int { set }": Expected((0, 1), (0, 1), []),
        "Probe::Box::var doubled: Int { get }": Expected((1, 1), (1, 1), probe),
        "Probe::Box::var watched { didSet }": Expected((1, 1), (1, 1), probe),
        "Probe::Box::var watched { willSet }": Expected((1, 1), (1, 1), probe),
        "Probe::Clamped::init(wrappedValue: Int)": Expected((3, 3), (1, 1), probe),
        "Probe::Clamped::var wrappedValue: Int { get }": Expected((1, 1), (1, 1), probe),
        "Probe::Clamped::var wrappedValue: Int { set }": Expected((0, 1), (0, 1), []),
        // The closure and the `+` operator's implicit closure fold in.
        "Probe::Counter::func add(_: [Int])": Expected((3, 3), (3, 3), probe),
        "Probe::Counter::func doubled() -> Int": Expected((3, 3), (1, 1), probe),
        "Probe::Counter::init()": Expected((1, 1), (1, 1), probe),
        "Probe::Settings::init()": Expected((1, 1), (1, 1), probe),
        // `||`'s autoclosure and the closure in it never ran: 1 of 3
        // regions, but their line ran through the body's region.
        "Probe::func anyLarge(_: [Int]) -> Bool": Expected((3, 3), (1, 3), probe),
        // Line 1 of a file with a byte order mark.
        "Probe::func bomFirst() -> Int": Expected((1, 1), (1, 1), probe),
        "Probe::func bomSecond() -> Int": Expected((3, 3), (1, 1), probe),
        // Overloads of one base name, apart.
        "Probe::func describe(_: Int) -> String": Expected((3, 3), (1, 1), probe),
        "Probe::func describe(_: String) -> String": Expected((0, 3), (0, 1), []),
        "Probe::func firstSecret() -> Int": Expected((3, 3), (1, 1), probe),
        "Probe::func fromHelper() -> Int": Expected((3, 3), (1, 1), probe),
        "Probe::func generatedHelper() -> Int": Expected((3, 3), (1, 1), probe),
        // `Side.left` as a function value: two entries with one region,
        // counts 1 and 2, deduplicated to one region.
        "Probe::func lefts(_: [Int]) -> [Side]": Expected((3, 3), (2, 2), probe),
        "Probe::func mode() -> String #if !(DEBUG)": Expected(reason: "no coverage data"),
        "Probe::func mode() -> String #if DEBUG": Expected((1, 1), (1, 1), probe),
        "Probe::func neverCalled() -> Int": Expected((0, 3), (0, 1), []),
        "Probe::func onlyKit() -> Int": Expected((3, 3), (1, 1), ["SwiftTestKitTests"]),
        // llvm-cov says 9 of 10 lines; the nested `inner` takes lines 3–5.
        "Probe::func outer(_: Bool) -> Int": Expected((6, 7), (3, 4), probe),
        "Probe::func outer(_: Bool) -> Int / func inner(_: Int) -> Int": Expected((0, 3), (0, 1), []),
        // Skipped `#if` lines (21–23, 25) aren't lines.
        "Probe::func platform() -> String": Expected((3, 3), (1, 1), probe),
        // A nested function on its parent's line: both get the line.
        "Probe::func sameLine() -> Int": Expected((1, 1), (1, 1), probe),
        "Probe::func sameLine() -> Int / func one() -> Int": Expected((0, 1), (0, 1), []),
        "Probe::func secondSecret() -> Int": Expected((0, 3), (0, 1), []),
        "Probe::func twice(_: Int) -> Int @ Sources/Probe/Counter.swift": Expected((3, 3), (1, 1), probe),
        // The default argument's closure, in the signature, folds in.
        "Probe::func withDefault(_: (Int) -> Int) -> Int": Expected((3, 3), (2, 2), probe),
        "Unlinked::func unlinked() -> Int": Expected(reason: "not linked into any test bundle")
    ]

    @Test("every production record of the fixture gets its hand-worked lines, regions and test targets, or a reason")
    func records() throws {
        let coverage = try #require(try CoverageFixture.report().coverage)

        #expect(coverage.records.map(\.key) == Self.expected.keys.sorted())
        for record in coverage.records {
            #expect(Expected(record) == Self.expected[record.key], "\(record.key)")
        }
    }

    @Test("""
        initialisers and lazy getters attach to their type, global closures and main.swift's globals to the \
        file, two files' private Secret types apart, each with the lines no record spans
        """)
    func attachments() throws {
        let coverage = try #require(try CoverageFixture.report().coverage)

        let tally = { (covered: Int, total: Int) in CoverageTally(covered: covered, total: total) }
        #expect(coverage.attachments == [
            CoverageAttachment(
                owner: "Sources/Exe/main.swift",
                attachedTo: .file,
                lines: tally(0, 2),
                regions: tally(0, 3)
            ),
            CoverageAttachment(
                owner: "Sources/Probe/Attached.swift",
                attachedTo: .file,
                lines: tally(1, 1),
                regions: tally(1, 1)
            ),
            CoverageAttachment(owner: "Probe::Box", attachedTo: .type, lines: tally(2, 2), regions: tally(4, 4)),
            CoverageAttachment(owner: "Probe::Counter", attachedTo: .type, lines: tally(1, 1), regions: tally(1, 1)),
            CoverageAttachment(
                owner: "Probe::Secret @ Sources/Probe/Attached.swift",
                attachedTo: .type,
                lines: tally(1, 1),
                regions: tally(1, 1)
            ),
            CoverageAttachment(
                owner: "Probe::Secret @ Sources/Probe/Secrets.swift",
                attachedTo: .type,
                lines: tally(0, 1),
                regions: tally(0, 1)
            ),
            CoverageAttachment(owner: "Probe::Settings", attachedTo: .type, lines: tally(1, 1), regions: tally(1, 1))
        ])
    }

    @Test("""
        an excluded file's entries are listed with their demangled names; the build's runners, the test files \
        and the nested package are only counted
        """)
    func unmappedAndDropped() throws {
        let coverage = try #require(try CoverageFixture.report().coverage)

        #expect(coverage.unmapped == [
            CoverageUnmapped(
                file: "Sources/Probe/Excluded.swift",
                startLine: 2,
                startColumn: 37,
                endLine: 4,
                endColumn: 2,
                count: 1,
                name: "$s5Probe14excludedHelperSiyF",
                demangled: "Probe.excludedHelper() -> Swift.Int",
                reason: "excluded"
            )
        ])
        #expect(coverage.dropped == CoverageDropped(build: 2, outsideRoot: 0, testFiles: 4, otherPackage: 1))
        #expect(coverage.bundles == ["ProbeTests", "SwiftTestKitTests"])
        #expect(coverage.tests == "passed")
        #expect(coverage.saturated.isEmpty)
    }

    @Test("each kept file's lines follow llvm-cov's file view, with partly run lines and the skipped ranges")
    func fileLines() throws {
        let coverage = try #require(try CoverageFixture.report().coverage)
        let files = Dictionary(uniqueKeysWithValues: coverage.files.map { ($0.file, $0) })

        #expect(coverage.files.map(\.file) == [
            "Sources/Exe/main.swift", "Sources/Probe/Accessors.swift", "Sources/Probe/Attached.swift",
            "Sources/Probe/Bom.swift", "Sources/Probe/Counter.swift", "Sources/Probe/Dependency.swift",
            "Sources/Probe/Generated.swift", "Sources/Probe/Nested.swift", "Sources/Probe/Overloads.swift",
            "Sources/Probe/Secrets.swift", "Sources/Probe/Wrappers.swift"
        ])
        // The file view gives the unrun `inner`'s first line its parent's
        // count (the documented same-line limit), and flags it.
        #expect(files["Sources/Probe/Nested.swift"]?.lines == [
            CoverageLineRun(start: 2, end: 2, count: 1, partlyRun: false),
            CoverageLineRun(start: 3, end: 3, count: 1, partlyRun: true),
            CoverageLineRun(start: 4, end: 5, count: 0, partlyRun: false),
            CoverageLineRun(start: 6, end: 6, count: 1, partlyRun: true),
            CoverageLineRun(start: 7, end: 7, count: 0, partlyRun: false),
            CoverageLineRun(start: 8, end: 11, count: 1, partlyRun: false),
            CoverageLineRun(start: 14, end: 14, count: 1, partlyRun: true),
            CoverageLineRun(start: 17, end: 17, count: 1, partlyRun: false),
            CoverageLineRun(start: 18, end: 18, count: 1, partlyRun: true),
            CoverageLineRun(start: 19, end: 19, count: 1, partlyRun: false)
        ])
        #expect(files["Sources/Probe/Overloads.swift"]?.skipped == [
            CoverageLineRange(start: 21, end: 23),
            CoverageLineRange(start: 25, end: 25)
        ])
        // llvm-cov's file view sums the two same-range entries (1 + 2).
        #expect(files["Sources/Probe/Wrappers.swift"]?.lines.first { $0.start == 36 }?.count == 3)
        #expect(files["Sources/Exe/main.swift"]?.lines == [
            CoverageLineRun(start: 1, end: 2, count: 0, partlyRun: false),
            CoverageLineRun(start: 4, end: 6, count: 1, partlyRun: false),
            CoverageLineRun(start: 7, end: 8, count: 0, partlyRun: false)
        ])
    }

    @Test("the run's options end with the map rule, and a scan without coverage has no coverage report")
    func optionsAndAbsence() throws {
        let report = try CoverageFixture.report()
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer { package.remove() }

        let status = report.collectors.first { $0.name == CoverageAdapter.name }
        #expect(status?.options.last == "map: " + CoverageMapper.rule)
        #expect(try package.scan(tools: SnapshotHarness.noTools).coverage == nil)
    }
}
