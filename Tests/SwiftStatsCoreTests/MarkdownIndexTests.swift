//
//  MarkdownIndexTests.swift
//  SwiftStatsCoreTests
//
//  The report's Build and index section (M7, design §10.1) on the Index
//  fixture's stored scan: the status and options, the units, the records
//  with and without a USR, the definitions with no record, the collisions,
//  the module edges and the type cycle as stored; the type-check part's
//  shape and counts (never its milliseconds, which a re-recording
//  changes); the compiler warnings by ID with their places, `IndexDep`'s
//  warning dropped as outside the root. The section
//  reads no run times. Type-check figures, cut lists, empty states and
//  carried statuses are in `MarkdownIndexTests+States.swift`.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Markdown build and index")
struct MarkdownIndexTests {
    /// The fixture's section from its status up to its USR tables.
    private static let head = [
        "Status: build ran; index ran.",
        "Build options: toolchain: Apple Swift version 9.9 (fake); .swift-version: absent; rebuild: root package "
            + "intermediates.",
        "",
        "Index store units: 22 kept, 0 variants, 0 duplicates; 0 stale and 0 other-module units (0 moved out of "
            + "the store); 0 system and 4 other-package units not read. Index records read: 22, with 1166 "
            + "occurrences.",
        "",
        "### USRs",
        "",
        "|  | Records with a USR | Secondary accessor USRs | `c:` USRs |",
        "| --- | --- | --- | --- |",
        "| production | 93 of 96 | 3 | 0 |",
        "| tests | 7 of 7 | 0 | 1 |",
        "| IndexApp | 0 of 1 | 0 | 0 |",
        "| IndexCore | 86 of 88 | 3 | 0 |",
        "| IndexCoreTests | 6 of 6 | 0 | 0 |",
        "| IndexTool | 1 of 1 | 0 | 0 |",
        "| IndexXCTests | 1 of 1 | 0 | 1 |",
        "| index-kit | 2 of 2 | 0 | 0 |",
        "| index-support | 4 of 4 | 0 | 0 |",
        "",
        "Every compiled record has a USR.",
        "Records without a USR: 3 (2 inactive #if branch; 1 top-level code).",
        "",
        "| Record | Reason |",
        "| --- | --- |",
        "| `<top-level code>` (Sources/IndexApp/main.swift:7) | top-level code |",
        "| `func flagged() -> Int #if INDEX_FIXTURE_FLAG` (Sources/IndexCore/TestOnly.swift:24) | inactive #if "
            + "branch |",
        "| `func buildMode() -> String #if !(DEBUG)` (Sources/IndexCore/TestOnly.swift:36) | inactive #if branch |"
    ]

    /// The fixture's disagreements, definitions with no record, collisions
    /// and coupling.
    private static let listings = [
        "USR and key disagreements:",
        "",
        "No USR and key disagree.",
        "",
        "Definitions with no record: 9 (9 requirement without a body).",
        "",
        "| Why | Symbol | USR | Place | Innermost record |",
        "| --- | --- | --- | --- | --- |",
        "| requirement without a body | `area()` | `s:9IndexCore5ShapeP4areaSiyF` | "
            + "Sources/IndexCore/Protocols.swift:4:10 | — |",
        "| requirement without a body | `greet()` | `s:9IndexCore7GreeterP5greetSSyF` | "
            + "Sources/IndexCore/Protocols.swift:21:10 | — |",
        "| requirement without a body | `getter:label` | `s:9IndexCore7LabeledP5labelSSvg` | "
            + "Sources/IndexCore/Protocols.swift:54:25 | — |",
        "| requirement without a body | `getter:rank` | `s:9IndexCore7LabeledP4rankSivg` | "
            + "Sources/IndexCore/Protocols.swift:56:21 | — |",
        "| requirement without a body | `setter:rank` | `s:9IndexCore7LabeledP4rankSivs` | "
            + "Sources/IndexCore/Protocols.swift:56:25 | — |",
        "| requirement without a body | `getter:fallback` | `s:9IndexCore7LabeledP8fallbackxvgZ` | "
            + "Sources/IndexCore/Protocols.swift:58:33 | — |",
        "| requirement without a body | `subscript(_:)` | `s:9IndexCore7LabeledPySSSicip` | "
            + "Sources/IndexCore/Protocols.swift:60:5 | — |",
        "| requirement without a body | `getter:subscript(_:)` | `s:9IndexCore7LabeledPySSSicig` | "
            + "Sources/IndexCore/Protocols.swift:60:38 | — |",
        "| requirement without a body | `setter:subscript(_:)` | `s:9IndexCore7LabeledPySSSicis` | "
            + "Sources/IndexCore/Protocols.swift:60:42 | — |",
        "",
        "Key collisions the USR separates:",
        "",
        "| Record | USR | Place |",
        "| --- | --- | --- |",
        "| `IndexCore::func measure(_: Data) -> Int @ Sources/IndexCore/Bytes.swift` | "
            + "`s:9IndexCore7measureySi10Foundation4DataVF` | Sources/IndexCore/Bytes.swift:6:6 |",
        "| `IndexCore::func measure(_: Data) -> Int @ Sources/IndexCore/Dependency.swift` | "
            + "`s:9IndexCore7measureySi0A6DepKit4DataVF` | Sources/IndexCore/Dependency.swift:11:6 |",
        "",
        "### Coupling",
        "",
        "Module edges:",
        "",
        "| From | To | Kind | References | Importing files |",
        "| --- | --- | --- | --- | --- |",
        "| IndexApp | IndexCore | package | 1 | 1 |",
        "| IndexApp | index-support | package | 1 | 1 |",
        "| IndexCore | IndexDepKit | dependency | — | 1 |",
        "| IndexCoreTests | IndexCore | package | 26 | 1 |",
        "| IndexCoreTests | index-kit | package | 2 | 1 |",
        "| IndexCoreTests | index-support | package | 2 | 1 |",
        "| IndexXCTests | IndexCore | package | 1 | 1 |",
        "",
        "Types referenced from other production modules:",
        "",
        "No type is referenced from another production module.",
        "",
        "Type cycles:",
        "",
        "| Cycle | Types |",
        "| --- | --- |",
        "| 1 | `IndexCore::Alpha`, `IndexCore::Beta` |",
        ""
    ]

    /// The fixture's warnings by ID, and their places.
    private static let warnings = [
        "8 compiler warnings, by diagnostic ID and group:",
        "",
        "| ID | Group | Count | First message |",
        "| --- | --- | --- | --- |",
        "| availability_deprecated | DeprecatedDeclaration | 1 | 'legacy()' is deprecated: use warned() |",
        "| bridged_warning | — | 1 | '#require(_:_:)' is redundant because 'Session(<br>            name: "
            + "\"spanning\"<br>        )' never equals 'nil' (from macro 'require') |",
        "| no_throw_in_try | UnnecessaryEffectMarker | 1 | no calls to throwing functions occur within 'try' "
            + "expression |",
        "| nonoptional_compare_to_nil | — | 1 | comparing non-optional value of type 'Int' to 'nil' always returns "
            + "true |",
        "| pbd_never_used | NoUsage | 1 | initialization of immutable value 'unusedTotal' was never used; consider "
            + "replacing with assignment to '_' or removing it |",
        "| pound_warning | — | 1 | remember to finish this |",
        "| unreachable_code_after_stmt | — | 1 | code after 'return' will never be executed |",
        "| variable_never_mutated | VariableNeverMutated | 1 | variable 'constant' was never mutated; consider "
            + "changing to 'let' constant |",
        "",
        "`bridged_warning` is the ID the compiler gives warnings raised in macro expansions (Swift Testing's "
            + "`#expect` and `#require` among them), whatever their kind.",
        "",
        "First places:",
        "",
        "| Place | ID | Message |",
        "| --- | --- | --- |",
        "| Sources/IndexCore/Locals.swift:26 | pbd_never_used | initialization of immutable value 'unusedTotal' was "
            + "never used; consider replacing with assignment to '_' or removing it |",
        "| Sources/IndexCore/Warnings.swift:3 | variable_never_mutated | variable 'constant' was never mutated; "
            + "consider changing to 'let' constant |",
        "| Sources/IndexCore/Warnings.swift:4 | availability_deprecated | 'legacy()' is deprecated: use warned() |",
        "| Sources/IndexCore/Warnings.swift:16 | unreachable_code_after_stmt | code after 'return' will never be "
            + "executed |",
        "| Sources/IndexCore/Warnings.swift:19 | pound_warning | remember to finish this |",
        "| Tests/IndexCoreTests/IndexCoreTests.swift:27 | nonoptional_compare_to_nil | comparing non-optional value "
            + "of type 'Int' to 'nil' always returns true |",
        "| Tests/IndexCoreTests/IndexCoreTests.swift:33 | no_throw_in_try | no calls to throwing functions occur "
            + "within 'try' expression |",
        "| Tests/IndexCoreTests/IndexCoreTests.swift:38 | bridged_warning | '#require(_:_:)' is redundant because "
            + "'Session(<br>            name: \"spanning\"<br>        )' never equals 'nil' (from macro 'require') |",
        "",
        "In plugin targets: 0. Also 1 dropped (under the build directory or outside the package root); 0 unmapped "
            + "(in a macro expansion without its origin, at an unknown place, or in a file changed during the scan)."
    ]

    /// The scope column and the functions-timed column of the type-check
    /// table: counts and names only, which a re-recording keeps.
    private static let timedRecords = [
        "production 93", "tests 7", "IndexApp 0", "IndexCore 86", "IndexCoreTests 6", "IndexTool 1",
        "IndexXCTests 1", "index-kit 2", "index-support 4"
    ]

    @Test("the fixture's section states its stored USRs, listings, coupling and warnings")
    func fixture() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let section = IndexReportHarness.section("Build and index", of: try IndexReportHarness.markdown(snapshot))

            #expect(Array(section.prefix(Self.head.count)) == Self.head)
            let listed = IndexReportHarness.part(section, from: "USR and key disagreements:", to: "### Type-check")
            #expect(listed == Self.listings)
            let warned = IndexReportHarness.part(section, from: "### Compiler warnings", to: "## ")
            #expect(Array(warned.dropFirst(2)) == Self.warnings)
        }
    }

    @Test("the type-check part lists every scope, the 20 slowest functions and the 10 slowest expressions")
    func typeCheckShape() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let section = IndexReportHarness.section("Build and index", of: try IndexReportHarness.markdown(snapshot))
            let part = IndexReportHarness.part(section, from: "### Type-check time", to: "### Compiler warnings")
            let rows = part.filter { $0.hasPrefix("| ") && $0.hasPrefix("| ---") == false }
            let scopes = rows.dropFirst().prefix(Self.timedRecords.count).map { row in
                let cells = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                return "\(cells[0]) \(cells[3])"
            }

            #expect(scopes == Self.timedRecords)
            #expect(part.contains("(first 20 of 100; the JSON lists all)"))
            #expect(part.contains("(first 10 of 97; the JSON lists all)"))
            // Header rows, 9 scopes, 20 functions and 10 expressions.
            #expect(rows.count == 3 + Self.timedRecords.count + 20 + 10)
            #expect(part.contains { $0.hasPrefix("On no record: 37 entries (") })
            let note = "Two builds' figures differ by a fifth to a third per function; the slowest functions are "
                + "what stays stable."
            #expect(part.last { $0.isEmpty == false } == note)
        }
    }

    @Test("the M7 sections read no run times: changed collector durations leave them byte for byte")
    func noRunTimes() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let made = try IndexReportHarness.made(snapshot)
            defer { made.store.remove() }
            let before = MarkdownReport.render(made.report)
            try SnapshotHarness.sqlite(made.store.url, "UPDATE collectorRun SET durationMilliseconds = "
                + "durationMilliseconds + 123456")
            let after = MarkdownReport.render(try IndexReportHarness.report(id: made.id, in: made.store.store))

            #expect(before != after)
            for heading in ["Build and index", "Dead code"] {
                let unchanged = IndexReportHarness.section(heading, of: before)
                #expect(unchanged == IndexReportHarness.section(heading, of: after))
            }
        }
    }

    @Test("report and top write schemas 6 and 5, the same bytes twice in both formats")
    func schemasAndDeterminism() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let made = try IndexReportHarness.made(snapshot)
            defer { made.store.remove() }
            let again = try IndexReportHarness.report(id: made.id, in: made.store.store)
            let json = try ScanReportEncoder.encode(made.report)
            let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]

            #expect(SnapshotReport.currentSchemaVersion == 6)
            #expect(TopReport.currentSchemaVersion == 5)
            #expect(object?["schemaVersion"] as? Int == 6)
            #expect(json == (try ScanReportEncoder.encode(again)))
            #expect(MarkdownReport.render(made.report) == MarkdownReport.render(again))
            for name in [SignalName.hiddenCoupling, .deadButTested, .testOnlyProduction] {
                let first = try #require(made.report.signals.first { $0.name == name })
                let second = try #require(again.signals.first { $0.name == name })
                let ranked = TopReport(snapshot: made.report.snapshot, signal: first, limit: 5)
                let top = try ScanReportEncoder.encode(ranked)
                let topObject = try JSONSerialization.jsonObject(with: top) as? [String: Any]
                #expect(topObject?["schemaVersion"] as? Int == 5)
                #expect(top == (try ScanReportEncoder.encode(
                    TopReport(snapshot: again.snapshot, signal: second, limit: 5)
                )))
                #expect(MarkdownSignals.top(first, limit: 5) == MarkdownSignals.top(second, limit: 5))
            }
        }
    }
}
