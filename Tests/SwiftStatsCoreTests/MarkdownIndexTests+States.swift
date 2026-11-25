//
//  MarkdownIndexTests+States.swift
//  SwiftStatsCoreTests
//
//  The Build and index section's other states (M7, design §10.1), on the
//  Index fixture's scan with hand-made index and build results: every
//  empty state's sentence; a record without a USR for an unexplained
//  reason dropping "Every compiled record has a USR."; a build whose only
//  warnings went unmapped saying none mapped, with the unmapped count; a
//  list cut at 50 rows while the JSON keeps them all; the type-check
//  table read from the roll-ups, and the slowest lists ordered and cut; a carried status with
//  its date apart; the section when the build didn't run, and when only
//  the index failed.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The Build and index section's empty, cut, carried and missing states.
extension MarkdownIndexTests {
    /// When the hand-made results were carried from.
    private static let collectedAt = "2026-11-24T09:00:00Z"
    /// What stands for the test's key in `timingsJSON`.
    private static let testToken = "@TEST@"
    /// The hand-made timings: a function, its nested local function and a
    /// test, as the scan JSON writes them.
    private static let timingsJSON = """
        [
          {"key": "IndexCore::func layout(_: Int) -> Int", "milliseconds": 30, "slowestExpression": 5},
          {"key": "IndexCore::func layout(_: Int) -> Int / func padded(_: Int) -> Int", "milliseconds": 20},
          {"key": "@TEST@", "milliseconds": 7, "slowestExpression": 9}
        ]
        """
    /// The hand-made attachments: a type's entries and a file's.
    private static let attachmentsJSON = """
        [
          {"owner": "IndexCore::Storage", "attachedTo": "type", "milliseconds": 4, "slowestExpression": 11},
          {"owner": "Sources/Kits/Support.swift", "attachedTo": "file", "milliseconds": 2}
        ]
        """
    /// The hand-made type-check totals: none of them the sum of its
    /// records' own figures (IndexCore's add to 34 with the type's 4, the
    /// tests' to 7), as hundredths rounded once per scope can give.
    private static let figureTotals = """
        {"project production": 37, "project tests": 8, "module IndexCore": 35, "module IndexCoreTests": 8,
         "module index-support": 2}
        """
    /// The scope table of the hand-made timings: each scope's roll-up,
    /// its total as given, the nested function's 20 ms among the maxima
    /// and timed records, and neither the type's nor the file's entries
    /// (their 11 ms expression is no record's).
    private static let figureScopes = [
        "|  | Function-body time (ms) | Slowest function (ms) | Functions timed | Slowest expression (ms) |",
        "| --- | --- | --- | --- | --- |",
        "| production | 37 | 30 | 2 | 5 |",
        "| tests | 8 | 7 | 1 | 9 |",
        "| IndexApp | 0 | — | 0 | — |",
        "| IndexCore | 35 | 30 | 2 | 5 |",
        "| IndexCoreTests | 8 | 7 | 1 | 9 |",
        "| IndexTool | 0 | — | 0 | — |",
        "| IndexXCTests | 0 | — | 0 | — |",
        "| index-kit | 0 | — | 0 | — |",
        "| index-support | 2 | — | 0 | — |"
    ]
    /// The slowest functions of the hand-made timings, the nested one with
    /// its own time.
    private static let figureSlowest = [
        "Slowest functions:",
        "",
        "| Function | Time (ms, including local functions) | Slowest expression (ms) |",
        "| --- | --- | --- |",
        "| `func layout(_: Int) -> Int` (Sources/IndexCore/Locals.swift:2) | 30 | 5 |",
        "| `func layout(_: Int) -> Int / func padded(_: Int) -> Int` (Sources/IndexCore/Locals.swift:3) | 20 | "
            + "— |",
        "| `IndexCoreTests::func onlyTests()` (Tests/IndexCoreTests/IndexCoreTests.swift:9) | 7 | 9 |",
        ""
    ]
    /// The slowest expressions of the hand-made timings.
    private static let figureExpressions = [
        "Slowest expressions, by record:",
        "",
        "| Function | Slowest expression (ms) |",
        "| --- | --- |",
        "| `IndexCoreTests::func onlyTests()` (Tests/IndexCoreTests/IndexCoreTests.swift:9) | 9 |",
        "| `func layout(_: Int) -> Int` (Sources/IndexCore/Locals.swift:2) | 5 |",
        ""
    ]

    /// `index` with `records` and `withoutRecord` in place of its own,
    /// and, when `empty`, no disagreements, collisions, module edges or
    /// type cycles.
    private static func index(
        _ index: IndexReport,
        records: [IndexRecordUSR],
        withoutRecord: [USRListing],
        empty: Bool
    ) -> IndexReport {
        IndexReport(
            store: index.store,
            libraryModules: index.libraryModules,
            records: records,
            definitions: index.definitions,
            disagreements: empty ? [] : index.disagreements,
            withoutRecord: withoutRecord,
            collisions: empty ? [] : index.collisions,
            moduleEdges: empty ? [] : index.moduleEdges,
            types: index.types.map { type in
                IndexTypeRow(
                    module: type.module,
                    typePath: type.typePath,
                    typeFile: type.typeFile,
                    usr: type.usr,
                    referrersSameModule: type.referrersSameModule,
                    referrersOtherModules: type.referrersOtherModules,
                    referrersTests: type.referrersTests,
                    cycle: empty ? nil : type.cycle
                )
            },
            familyReferences: index.familyReferences,
            familyTypeReferences: index.familyTypeReferences,
            files: index.files
        )
    }

    /// `report`'s status of collector `name`.
    private static func status(_ name: String, of report: ScanReport) throws -> CollectorStatus {
        try #require(report.collectors.first { $0.name == name })
    }

    /// `status` with `state` and `reason`.
    private static func status(
        _ status: CollectorStatus,
        _ state: CollectorState,
        _ reason: String?
    ) -> CollectorStatus {
        CollectorStatus(
            name: status.name,
            state: state,
            version: status.version,
            reason: reason,
            options: status.options
        )
    }

    /// `model` at `line`, held by no record.
    private static func listing(_ model: USRListing, line: Int) -> USRListing {
        USRListing(
            kind: model.kind,
            subreason: model.subreason,
            usr: model.usr,
            key: nil,
            symbolKind: model.symbolKind,
            name: model.name,
            file: model.file,
            line: line,
            column: model.column
        )
    }

    /// `build` with `unmapped` warnings left unmapped.
    private static func build(_ build: BuildReport, unmapped: Int) -> BuildReport {
        BuildReport(
            complete: build.complete,
            records: build.records,
            attachments: build.attachments,
            unmapped: build.unmapped,
            dropped: build.dropped,
            totals: build.totals,
            changedFiles: build.changedFiles,
            unparsedTimingLines: build.unparsedTimingLines,
            escapedLines: build.escapedLines,
            otherWarningLines: build.otherWarningLines,
            warningsDropped: build.warningsDropped,
            warningsUnmapped: unmapped,
            pluginWarnings: build.pluginWarnings
        )
    }

    /// Checks `lines`, the section of the fixture given the hand-made
    /// timings and attachments.
    private static func checkTypeCheckFigures(_ lines: [String]) {
        let part = IndexReportHarness.part(lines, from: "### Type-check time", to: "On no record")

        #expect(lines.contains("Timings are incomplete: the build found no root intermediates to remove, so files "
            + "it didn't recompile have no timings."))
        #expect(part.contains { $0.hasPrefix("57 ms of function-body time from 4 function-body and 3 expression") })
        #expect(Array(part.drop { $0.hasPrefix("|  |") == false }.prefix(figureScopes.count)) == figureScopes)
        #expect(IndexReportHarness.part(part, from: "Slowest functions:", to: "Slowest expressions") == figureSlowest)
        #expect(IndexReportHarness.part(part, from: "Slowest expressions, by record:", to: "On no record")
            == figureExpressions)
        #expect(lines.contains("On no record: 1 entries (2 ms) synthesized members, 3 entries (4 ms) in macro "
            + "expansions. Left out: 5 entries (6 ms) under the build directory, 7 entries (8 ms) outside the "
            + "package root, 9 entries (10 ms) in files the scan didn't parse, 11 entries (12 ms) in files "
            + "changed during the scan."))
    }

    @Test("""
        every empty list has its sentence, and an unexplained record without a USR drops "Every compiled record \
        has a USR."
        """)
    func emptyStates() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let held = try #require(snapshot.report.index)
            let indexStatus = try Self.status(IndexAdapter.name, of: snapshot.report)
            let none = Self.index(held, records: held.records, withoutRecord: [], empty: true)
            var emptied = snapshot.report.with(index: none, status: indexStatus)
            emptied.findings = emptied.findings.filter { $0.tool != WarningReader.tool }
            let records = held.records.map { record in
                record.key == IndexHarness.onlyTestsCall
                    ? IndexRecordUSR(key: record.key, usr: nil, usrAccessor: nil, reason: .unexplained, coupling: nil)
                    : record
            }
            let unexplained = snapshot.report.with(
                index: Self.index(held, records: records, withoutRecord: held.withoutRecord, empty: false),
                status: indexStatus
            )

            let empty = MarkdownIndex.render(emptied)
            #expect(empty.contains("Every compiled record has a USR."))
            for sentence in [
                "No USR and key disagree.", "Every definition the index read has a record.",
                "No key collision to separate.", "No module edges.",
                "No type is referenced from another production module.", "No type cycles.",
                "No compiler warnings; 1 dropped (under the build directory or outside the package root)."
            ] {
                #expect(empty.contains(sentence))
            }
            let lines = MarkdownIndex.render(unexplained)
            #expect(lines.contains("Every compiled record has a USR.") == false)
            #expect(lines.contains("Records without a USR: 4 (2 inactive #if branch; 1 top-level code; 1 "
                + "unexplained)."))
            #expect(lines.contains("| `func onlyTestsCall() -> Int` (Sources/IndexCore/TestOnly.swift:7) | "
                + "unexplained |"))
        }
    }

    @Test("""
        a build whose only warnings went unmapped says no warning mapped to the package, with the unmapped count, \
        not "No compiler warnings"
        """)
    func onlyUnmappedWarnings() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let held = try #require(snapshot.report.build)
            let status = try Self.status(BuildAdapter.name, of: snapshot.report)
            var report = snapshot.report.with(
                build: Self.build(held, unmapped: 3),
                totals: TypeCheckTotals(rollups: snapshot.report.rollups),
                status: status
            )
            report.findings = report.findings.filter { $0.tool != WarningReader.tool }
            let lines = MarkdownIndex.render(report)

            #expect(lines.contains("No compiler warnings mapped to the package; 1 dropped (under the build directory "
                + "or outside the package root); 3 unmapped (in a macro expansion without its origin, at an unknown "
                + "place, or in a file changed during the scan)."))
            #expect(lines.contains { $0.hasPrefix("No compiler warnings;") } == false)
        }
    }

    @Test("a list prints its first 50 rows and says how many there are, while the JSON keeps them all")
    func capped() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let held = try #require(snapshot.report.index)
            let first = try #require(held.withoutRecord.first)
            let listings = (1...55).map { Self.listing(first, line: $0) }
            let status = try Self.status(IndexAdapter.name, of: snapshot.report)
            let report = snapshot.report.with(
                index: Self.index(held, records: held.records, withoutRecord: listings, empty: false),
                status: status
            )
            let made = try IndexReportHarness.made(ScannedSnapshot(info: snapshot.info, report: report))
            defer { made.store.remove() }
            let section = IndexReportHarness.section("Build and index", of: MarkdownReport.render(made.report))
            let lead = "Definitions with no record: 55 (55 requirement without a body)."
            let part = IndexReportHarness.part(section, from: lead, to: "Key collisions")
            let encoded = try ScanReportEncoder.encode(made.report)
            let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            let scan = json?["scan"] as? [String: Any]
            let stored = (scan?["index"] as? [String: Any])?["withoutRecord"] as? [Any]

            #expect(part.count { $0.hasPrefix("| requirement without a body |") } == 50)
            #expect(part.contains("(first 50 of 55; the JSON lists all)"))
            #expect(part.contains { $0.hasSuffix("Sources/IndexCore/Protocols.swift:50:10 | — |") })
            #expect(part.contains { $0.hasSuffix("Sources/IndexCore/Protocols.swift:51:10 | — |") } == false)
            #expect(stored?.count == 55)
        }
    }

    @Test("""
        the type-check table reads each part's and module's roll-up, its total as the scan gave it; the slowest \
        functions and expressions come highest first
        """)
    func typeCheckFigures() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let keys = Set(snapshot.report.records.map(\.key))
            let test = try #require(keys.sorted().first { $0.hasSuffix("func onlyTests()") })
            let timings = try JSONDecoder().decode(
                [BuildRecordTiming].self,
                from: Data(Self.timingsJSON.replacingOccurrences(of: Self.testToken, with: test).utf8)
            )
            #expect(timings.allSatisfy { keys.contains($0.key) })
            let attachments = try JSONDecoder().decode([BuildAttachment].self, from: Data(Self.attachmentsJSON.utf8))
            let build = try BuildReport.sample(records: timings, attachments: attachments)
            let status = try Self.status(BuildAdapter.name, of: snapshot.report)
            let totals = try TypeCheckTotals.given(Self.figureTotals)
            let report = snapshot.report.with(build: build, totals: totals, status: status)
            Self.checkTypeCheckFigures(MarkdownIndex.render(report))
        }
    }

    @Test("the slowest functions are cut at 20 and the slowest expressions at 10, saying how many there are")
    func typeCheckCut() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let status = try Self.status(BuildAdapter.name, of: snapshot.report)
            let many = snapshot.report.records.prefix(25).enumerated().map { offset, record in
                BuildRecordTiming(key: record.key, milliseconds: offset + 1, slowestExpression: offset + 1)
            }
            let build = try BuildReport.sample(records: many, attachments: [])
            let cut = MarkdownIndex.render(snapshot.report.with(build: build, totals: .empty, status: status))
            let rows = IndexReportHarness.part(cut, from: "Slowest functions:", to: "Slowest expressions")
                .filter { $0.hasPrefix("| `") }

            #expect(rows.count == 20)
            #expect(rows.first?.hasSuffix("| 25 | 25 |") == true)
            #expect(rows.last?.hasSuffix("| 6 | 6 |") == true)
            #expect(cut.contains("(first 20 of 25; the JSON lists all)"))
            #expect(cut.contains("(first 10 of 25; the JSON lists all)"))
        }
    }

    @Test("a carried status shows its date apart from the reason the carried run gave")
    func carried() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let carried = CollectorRunInfo.carriedPrefix + Self.collectedAt
            let build = try Self.status(BuildAdapter.name, of: snapshot.report)
            let index = try Self.status(IndexAdapter.name, of: snapshot.report)
            let report = snapshot.report
                .with(
                    build: snapshot.report.build,
                    totals: TypeCheckTotals(rollups: snapshot.report.rollups),
                    status: Self.status(build, .ran, carried + "; 2 files changed")
                )
                .with(index: snapshot.report.index, status: Self.status(index, .ran, carried))
            let lines = MarkdownIndex.render(report)

            #expect(Array(lines.prefix(2)) == [
                "Status: build ran, 2 files changed; index ran.",
                "Carried from the scan of \(Self.collectedAt): the tree, its records, types and files are unchanged "
                    + "since."
            ])
            #expect(MarkdownCarry.state(Self.status(index, .failed, carried + "; exited 1")) == "failed, exited 1")
            #expect(MarkdownCarry.carried(Self.status(index, .skipped, "not requested")) == nil)
            #expect(MarkdownCarry.state(nil) == "not in this snapshot")
        }
    }

    @Test("without the build the section says why; with only the index failed it keeps the build's parts")
    func missing() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let build = try Self.status(BuildAdapter.name, of: snapshot.report)
            let index = try Self.status(IndexAdapter.name, of: snapshot.report)
            let skipped = snapshot.report
                .with(build: nil, totals: .empty, status: Self.status(build, .skipped, BuildAdapter.notRequestedReason))
                .with(index: nil, status: Self.status(index, .skipped, BuildAdapter.notRequestedReason))
            let failed = snapshot.report.with(index: nil, status: Self.status(index, .failed, "the reader failed"))
            let lines = MarkdownIndex.render(failed)

            #expect(MarkdownIndex.render(skipped) == ["Not collected: skipped, not requested; scan --index runs it."])
            #expect(lines.first == "Status: build ran; index failed, the reader failed.")
            #expect(lines.contains("### USRs") == false)
            #expect(lines.contains("### Type-check time"))
            #expect(lines.contains("### Compiler warnings"))
        }
    }
}
