//
//  IntegerEdgesPBT+Findings.swift
//  SwiftStatsCoreTests
//
//  P15.1's findings path: a SwiftLint report and a SwiftProjectLint report
//  read as their collectors read them (`decode(_:)`, then
//  `finding(for:root:)`), then attached by `FindingMapper`, every number
//  an integer edge. SwiftProjectLint's report is refused unless its schema
//  version is 1; every place comes back with its line and column as
//  written, on `first()` when it is line 1 of the scanned file (the one
//  edge line a record holds), on the file at any other line, and
//  unscanned in a file the scan never read. Its examples, and a meta-test
//  that feeds a planted defect's findings (lines read as `Int32`,
//  clamping) to its check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P15.1's findings path.
extension IntegerEdgesPBT {
    /// What reading both reports and attaching their findings gave.
    struct ReadFindings {
        /// SwiftLint's findings, attached, or the failure reading them gave.
        let swiftLint: Result<[Finding], any Error>
        /// SwiftProjectLint's, or the failure reading them gave.
        let projectLint: Result<[Finding], any Error>
    }

    /// The findings path's base runs, over the engine's 100: two small
    /// reports cost tens of microseconds. The rarest antecedent, a
    /// SwiftProjectLint place on `first()`, comes in 125 of the
    /// meta-test's 1,000 drafts (design D14: `(1 - 0.125)^150`, about
    /// 2 * 10^-9, is the most a run misses it; 100 runs would miss it
    /// about 1.6 * 10^-6 of the time).
    static let findingRuns = 150
    /// What the findings path's tally counts when SwiftProjectLint's
    /// report is read.
    static let schemaRead = "SwiftProjectLint's schema read"
    /// What it counts when a SwiftLint place is attached to a record.
    static let violationOnRecord = "a violation on a record"
    /// What it counts when a SwiftProjectLint place is attached to one.
    static let issueOnRecord = "an issue on a record"
    /// What it counts when a place lies in a file the scan never read.
    static let unscannedPlace = "a place unscanned"
    /// The antecedents the findings path must reach at least once each.
    static let findingAntecedents = [
        mapped, failed, unknown, schemaRead, violationOnRecord, issueOnRecord, unscannedPlace, largest, zero
    ]

    /// Reports whose violations lie at 1:`Int.max` of the scanned file and
    /// `Int.max`:0 of a file never read, and whose schema-1 issue lies at
    /// lines 1 and `Int.max - 1` of the scanned file.
    static let largestFindings = LintEdgeDraft(
        violations: [
            LintEdgeDraft.Violation(scanned: true, line: 1, column: Int.max),
            LintEdgeDraft.Violation(scanned: false, line: Int.max, column: 0)
        ],
        schemaVersion: 1,
        issueScanned: true,
        issueLines: [1, Int.max - 1]
    )

    /// Where a place of `file` at `line` attaches: unscanned outside the
    /// scanned file, on `first()` at line 1 of it, else on the file.
    static func expectedTarget(file: String, line: Int) -> FindingTarget {
        guard file == IntegerEdgeGen.plainFile else {
            return .unscanned
        }
        return line == 1 ? .function : .file
    }

    /// The classes `draft` falls in, for the findings path's tally and the
    /// generator's meta-test.
    static func findingLabels(of draft: LintEdgeDraft) -> [String] {
        let read = draft.schemaVersion == SwiftProjectLintAdapter.schemaVersion
        let violationTargets = draft.violations.map { expectedTarget(file: $0.file, line: $0.line) }
        let issueTargets = read ? draft.issueLines.map { expectedTarget(file: draft.issueFile, line: $0) } : []
        let targets = violationTargets + issueTargets
        let numbers = draft.violations.flatMap { [$0.line, $0.column] } + [draft.schemaVersion] + draft.issueLines
        return [
            (read, schemaRead),
            (read == false, failed),
            (targets.contains(.function), mapped),
            (targets.contains { $0 != .function }, unknown),
            (violationTargets.contains(.function), violationOnRecord),
            (issueTargets.contains(.function), issueOnRecord),
            (targets.contains(.unscanned), unscannedPlace)
        ]
        .filter(\.0)
        .map(\.1) + edgeLabels(numbers)
    }

    /// The laws `location`, a place drafted in `file` at `line` and
    /// `column`, must meet on `library`.
    static func checkLocation(
        _ location: FindingLocation,
        file: String,
        line: Int,
        column: Int?,
        library: Library
    ) -> [(holds: Bool, law: String)] {
        let target = expectedTarget(file: file, line: line)
        let owner = target == .function ? library.firstKey : nil
        return [
            (
                (location.file, location.line, location.column) == (file, line, column),
                "reads \(file):\(line):\(String(describing: column)) as \(location.file):"
                    + "\(String(describing: location.line)):\(String(describing: location.column))"
            ),
            (
                location.attachedTo == target && location.owner == owner,
                "attaches \(file):\(line) to \(location.attachedTo) \(String(describing: location.owner)), expected "
                    + "\(target) \(String(describing: owner))"
            )
        ]
    }

    /// Whether `read`, what `draft`'s reports gave on `library`, is what
    /// the collectors' and the mapper's rules give: SwiftLint's violations
    /// each read and attached, SwiftProjectLint's report refused for a
    /// schema version other than 1 and otherwise its issue's places read
    /// and attached. Records an issue for each law that fails.
    static func checkFindings(_ draft: LintEdgeDraft, read: ReadFindings, library: Library) -> Bool {
        let subject = "attaching the lint findings"
        var laws: [(holds: Bool, law: String)] = []
        switch read.swiftLint {
        case .success(let findings):
            let locations = findings.flatMap(\.locations)
            laws.append((locations.count == draft.violations.count, "gives \(locations.count) violations"))
            for (location, violation) in zip(locations, draft.violations) {
                laws += checkLocation(
                    location,
                    file: violation.file,
                    line: violation.line,
                    column: violation.column,
                    library: library
                )
            }

        case .failure(let error):
            laws.append((false, "fails to read the SwiftLint report: \(error)"))
        }
        let refused = draft.schemaVersion != SwiftProjectLintAdapter.schemaVersion
        switch read.projectLint {
        case .success(let findings):
            let locations = findings.flatMap(\.locations)
            laws.append((refused == false, "reads a report of schema \(draft.schemaVersion)"))
            laws.append((locations.count == draft.issueLines.count, "gives \(locations.count) places"))
            for (location, line) in zip(locations, draft.issueLines) {
                laws += checkLocation(location, file: draft.issueFile, line: line, column: nil, library: library)
            }

        case .failure(let error):
            let named = "schemaVersion \(draft.schemaVersion);"
            laws.append((refused && "\(error)".contains(named), "refuses the report as \(error), not naming \(named)"))
        }
        return holds(laws, subject: subject)
    }

    /// Counts in `tally` what `read` shows: a place on a record, and one
    /// that isn't.
    static func tallyFindings(_ read: ReadFindings, in tally: AntecedentTally) {
        let findings = ((try? read.swiftLint.get()) ?? []) + ((try? read.projectLint.get()) ?? [])
        let targets = findings.flatMap(\.locations).map(\.attachedTo)
        if targets.contains(.function) {
            tally.fire(mapped)
        }
        if targets.contains(where: { $0 != .function }) {
            tally.fire(unknown)
        }
    }

    /// `read` with every line kept as an `Int32` would keep it, clamping:
    /// the planted defect.
    static func clampedLines(_ read: ReadFindings) -> ReadFindings {
        let clamp = { (findings: [Finding]) in
            findings.map { finding in
                Finding(
                    tool: finding.tool,
                    rule: finding.rule,
                    category: finding.category,
                    kind: finding.kind,
                    severity: finding.severity,
                    message: finding.message,
                    symbol: finding.symbol,
                    locations: finding.locations.map { location in
                        FindingLocation(
                            file: location.file,
                            line: location.line.map { Int(Int32(clamping: $0)) },
                            column: location.column,
                            attachedTo: location.attachedTo,
                            owner: location.owner
                        )
                    }
                )
            }
        }
        return ReadFindings(swiftLint: read.swiftLint.map(clamp), projectLint: read.projectLint.map(clamp))
    }

    // MARK: P15.1, findings

    /// Invariant: SwiftLint's and SwiftProjectLint's reports, every number
    /// an integer edge, read with each place's line and column as written,
    /// attached to the record holding its line, else to its file, or
    /// unscanned, SwiftProjectLint's refused for a schema other than 1,
    /// and nothing traps.
    /// Why it holds: the adapters' `decode(_:)` and `finding(for:root:)`
    /// (PRD §7.7, §7.15: the schema version is checked first), and
    /// `FindingMapper`'s header (PRD §7.16).
    /// Why it might not: the scanned file's only record holding an edge
    /// line is `first()`, alone on line 1, and no type holds one, as
    /// `libraryIsAsStated` pins; the file never read exists in the package
    /// (a path is made relative through the files it names).
    /// Oracle: postconditions from the rules above; planted defects: a
    /// record's last line left out of the lines it holds,
    /// SwiftProjectLint's schema left unchecked, and (meta-test) lines kept
    /// as `Int32`, clamping, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        lint reports at the integer edges keep every place as written, attached by its line, \
        SwiftProjectLint's refused for another schema, and nothing traps
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func lintEdgesMap() async throws {
        let library = try Library()
        defer { library.remove() }
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        let mapper = FindingMapper(measured: library.measured)
        let root = URL(fileURLWithPath: library.root)
        await propertyCheck(count: PBTBudget.runs(Self.findingRuns), input: IntegerEdgeGen.lints) { draft in
            PBTTrace.note(draft)
            Self.findingLabels(of: draft).filter { $0 != Self.mapped && $0 != Self.unknown }.forEach(tally.fire)
            let read = ReadFindings(
                swiftLint: Result {
                    try SwiftLintAdapter.decode(draft.swiftLintReport(root: library.root))
                        .map { mapper.finding(for: SwiftLintAdapter.finding(for: $0, root: root)) }
                },
                projectLint: Result {
                    try SwiftProjectLintAdapter.decode(draft.projectLintReport(root: library.root)).issues
                        .map { mapper.finding(for: SwiftProjectLintAdapter.finding(for: $0, root: root)) }
                }
            )
            Self.tallyFindings(read, in: tally)
            if Self.checkFindings(draft, read: read, library: library) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.findingAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        violations at 1:Int.max and Int.max:0 attach to first() and as unscanned, and an issue at lines 1 and \
        Int.max - 1 to first() and the file
        """)
    func largestFindingsAttach() throws {
        let library = try Library()
        defer { library.remove() }
        let mapper = FindingMapper(measured: library.measured)
        let root = URL(fileURLWithPath: library.root)
        let draft = Self.largestFindings

        let read = ReadFindings(
            swiftLint: Result {
                try SwiftLintAdapter.decode(draft.swiftLintReport(root: library.root))
                    .map { mapper.finding(for: SwiftLintAdapter.finding(for: $0, root: root)) }
            },
            projectLint: Result {
                try SwiftProjectLintAdapter.decode(draft.projectLintReport(root: library.root)).issues
                    .map { mapper.finding(for: SwiftProjectLintAdapter.finding(for: $0, root: root)) }
            }
        )

        #expect(Self.checkFindings(draft, read: read, library: library))
        #expect(try read.swiftLint.get().flatMap(\.locations).map(\.attachedTo) == [.function, .unscanned])
        #expect(try read.projectLint.get().flatMap(\.locations).map(\.attachedTo) == [.function, .file])
    }

    @Test("""
        SwiftProjectLint reports of schema 0 and Int.max are refused, naming the version, and SwiftLint's still read
        """)
    func otherSchemasRefused() throws {
        let library = try Library()
        defer { library.remove() }
        let mapper = FindingMapper(measured: library.measured)
        let root = URL(fileURLWithPath: library.root)
        for version in [0, Int.max] {
            let draft = LintEdgeDraft(
                violations: [LintEdgeDraft.Violation(scanned: true, line: 0, column: 1)],
                schemaVersion: version,
                issueScanned: false,
                issueLines: [Int.max]
            )

            let read = ReadFindings(
                swiftLint: Result {
                    try SwiftLintAdapter.decode(draft.swiftLintReport(root: library.root))
                        .map { mapper.finding(for: SwiftLintAdapter.finding(for: $0, root: root)) }
                },
                projectLint: Result {
                    try SwiftProjectLintAdapter.decode(draft.projectLintReport(root: library.root)).issues
                        .map { mapper.finding(for: SwiftProjectLintAdapter.finding(for: $0, root: root)) }
                }
            )

            #expect(Self.checkFindings(draft, read: read, library: library))
            #expect(throws: AdapterError.self) { try read.projectLint.get() }
        }
    }

    @Test("the findings path's check detects a planted defect: lines kept as Int32, clamping")
    func findingCheckDetectsClampedLines() throws {
        let library = try Library()
        defer { library.remove() }
        let mapper = FindingMapper(measured: library.measured)
        let root = URL(fileURLWithPath: library.root)
        let draft = Self.largestFindings
        let read = ReadFindings(
            swiftLint: Result {
                try SwiftLintAdapter.decode(draft.swiftLintReport(root: library.root))
                    .map { mapper.finding(for: SwiftLintAdapter.finding(for: $0, root: root)) }
            },
            projectLint: Result {
                try SwiftProjectLintAdapter.decode(draft.projectLintReport(root: library.root)).issues
                    .map { mapper.finding(for: SwiftProjectLintAdapter.finding(for: $0, root: root)) }
            }
        )

        PlantedDefect.expectDetected("lines kept as Int32, clamping", sourceLocation: #_sourceLocation) {
            Self.checkFindings(draft, read: Self.clampedLines(read), library: library)
        }
    }
}
