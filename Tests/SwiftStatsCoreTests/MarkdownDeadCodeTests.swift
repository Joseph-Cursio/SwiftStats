//
//  MarkdownDeadCodeTests.swift
//  SwiftStatsCoreTests
//
//  The report's Dead code section (M7, design §10.1) on the Index
//  fixture's stored scan with the fake outskirts' recorded runs: the
//  status, outskirts' version and build, the runs' result counts and the
//  retained modules, the unused production declarations by kind and one
//  by one with how they cover records, the dead records and both ratios
//  per production module, the results left out and outskirts' limits;
//  then the other hints and a build's label, and the section when
//  outskirts failed.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Markdown dead code")
struct MarkdownDeadCodeTests {
    /// The fixture's section up to outskirts' limits.
    private static let fixtureLines = [
        "Status: ran.",
        "outskirts 3.28.0, build sha256:fa462994fb.",
        "Results per run (roots: test targets are roots; production: they aren't): roots 8, production 10.",
        "Retained public modules (library products): IndexCore, index-kit.",
        "",
        "### Unused declarations",
        "",
        "Unused production declarations by kind:",
        "",
        "| Kind | Roots run | Production run |",
        "| --- | --- | --- |",
        "| function | 3 | 5 |",
        "| type | 1 | 1 |",
        "| extension | 1 | 1 |",
        "| property | 1 | 1 |",
        "| enumCase | 0 | 0 |",
        "| parameter | 0 | 0 |",
        "| import | 0 | 0 |",
        "| other | 0 | 0 |",
        "",
        "No other hints.",
        "",
        "Unused production declarations:",
        "",
        "| Run | Kind | Name | Place | Via | Records covered |",
        "| --- | --- | --- | --- | --- | --- |",
        "| roots | var.instance | `unusedComputed` | Sources/IndexCore/Accessors.swift:65 | property | 1 |",
        "| roots | function.free | `unusedHelper()` | Sources/IndexCore/Locals.swift:27 | usr | 1 |",
        "| roots | function.free | `neverCalled()` | Sources/IndexCore/TestOnly.swift:13 | usr | 1 |",
        "| roots | extension.struct | `Unused` | Sources/IndexCore/Unused+Extra.swift:1 | extension | 1 |",
        "| roots | struct | `Unused` | Sources/IndexCore/Unused.swift:3 | type | 2 |",
        "| roots | function.free | `relay()` | Sources/Kits/Relay.swift:3 | usr | 1 |",
        "| production | var.instance | `unusedComputed` | Sources/IndexCore/Accessors.swift:65 | property | 1 |",
        "| production | function.free | `unusedHelper()` | Sources/IndexCore/Locals.swift:27 | usr | 1 |",
        "| production | function.free | `onlyTestsCall()` | Sources/IndexCore/TestOnly.swift:7 | usr | 1 |",
        "| production | function.free | `neverCalled()` | Sources/IndexCore/TestOnly.swift:13 | usr | 1 |",
        "| production | extension.struct | `Unused` | Sources/IndexCore/Unused+Extra.swift:1 | extension | 1 |",
        "| production | struct | `Unused` | Sources/IndexCore/Unused.swift:3 | type | 2 |",
        "| production | function.free | `relay()` | Sources/Kits/Relay.swift:3 | usr | 1 |",
        "| production | function.free | `parseLine(_:)` | Sources/Kits/Support.swift:5 | usr | 1 |",
        "",
        "### Dead records and the test-to-code ratio",
        "",
        "|  | Dead with tests as roots | Production-dead | Dead lines | Test / production | Test / (production − "
            + "dead) | Unused declarations without a line count |",
        "| --- | --- | --- | --- | --- | --- | --- |",
        "| production | 7 | 9 | 25 | 0.08 | 0.08 | 0 |",
        "| IndexApp | 0 | 0 | 0 | 0 | 0 | 0 |",
        "| IndexCore | 6 | 7 | 22 | 0.08 | 0.09 | 0 |",
        "| IndexTool | 0 | 0 | 0 | 0 | 0 | 0 |",
        "| index-kit | 1 | 1 | 3 | 4.50 | 9 | 0 |",
        "| index-support | 0 | 1 | 0 | 1.23 | 1.23 | 0 |",
        "",
        "Records are function records; dead lines are the stripped lines of the outermost declarations the roots "
            + "run finds unused.",
        "",
        "Results left out, per class:",
        "",
        "| Run | Test targets | Local declarations | Outside the package | Under the build directory | Unscanned "
            + "files | Files changed during the scan |",
        "| --- | --- | --- | --- | --- | --- | --- |",
        "| roots | 0 | 1 | 1 | 0 | 0 | 0 |",
        "| production | 0 | 1 | 1 | 0 | 0 | 0 |",
        "",
        "### outskirts' limits",
        ""
    ]

    /// Three entries like `model` with hints other than unused: two
    /// `assignOnlyProperty` in the roots run, one `redundantProtocol` in
    /// the production run.
    private static func hinted(like model: DeadCodeDeclaration) -> [DeadCodeDeclaration] {
        let hints: [(DeadCodeRun, String)] = [
            (.roots, "assignOnlyProperty"), (.production, "redundantProtocol"), (.roots, "assignOnlyProperty")
        ]
        return hints.enumerated().map { offset, entry in
            DeadCodeDeclaration(
                run: entry.0,
                ordinal: model.ordinal + hints.count + offset,
                hint: entry.1,
                hintText: nil,
                kind: model.kind,
                name: model.name,
                accessibility: model.accessibility,
                attributes: [],
                modifiers: [],
                ids: [],
                modules: model.modules,
                entryClass: .production,
                file: model.file,
                line: model.line,
                column: model.column,
                place: model.place,
                owner: model.owner,
                module: model.module,
                strippedLines: nil
            )
        }
    }

    /// `run` with the identity `identity` and the label `label`.
    private static func labelled(_ run: CollectorRunInfo, identity: String, label: String) -> CollectorRunInfo {
        CollectorRunInfo(
            name: run.name,
            state: run.state,
            reason: run.reason,
            version: run.version,
            identity: identity,
            identityLabel: label,
            options: run.options,
            durationMilliseconds: run.durationMilliseconds
        )
    }

    @Test("the fixture's section states outskirts' runs, the unused declarations, dead records, ratios and limits")
    func fixture() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let section = IndexReportHarness.section("Dead code", of: try IndexReportHarness.markdown(snapshot))

            #expect(Array(section.prefix(Self.fixtureLines.count)) == Self.fixtureLines)
            #expect(section.dropFirst(Self.fixtureLines.count).count == 5)
            #expect(section.dropFirst(Self.fixtureLines.count).allSatisfy { $0.hasPrefix("- ") })
            #expect(section.last == "- Unused local variables come back as unused globals once locals are indexed; "
                + "SwiftStats classes them local and leaves them out.")
        }
    }

    @Test("other hints are counted per run and hint, and a labelled build shows its label")
    func hintsAndLabel() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let dead = try #require(snapshot.report.deadCode)
            let model = try #require(dead.declarations.last { $0.run == .production && $0.isUnusedProduction })
            let added = try IndexHarness.adding(Self.hinted(like: model), to: snapshot)
            let run = try #require(added.info.collectors.first { $0.name == PeripheryAdapter.name })
            let labelled = Self.labelled(run, identity: "sha256:742c60c41c0123456789", label: "git:a1e5d6e1 (3.28.0)")
            let lines = MarkdownDeadCode.render(added.report, runs: [labelled])

            #expect(lines.contains("outskirts 3.28.0, build sha256:742c60c41c (git:a1e5d6e1 (3.28.0))."))
            #expect(lines.contains("Other hints: roots run 2 assignOnlyProperty; production run 1 redundantProtocol."))
        }
    }

    @Test("when outskirts failed, the section says so and nothing else")
    func failed() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let status = try #require(snapshot.report.collectors.first { $0.name == PeripheryAdapter.name })
            let failed = CollectorStatus(
                name: status.name,
                state: .failed,
                version: nil,
                reason: "outskirts scan (roots) exited 1: boom",
                options: []
            )
            let lines = MarkdownDeadCode.render(snapshot.report.with(deadCode: nil, status: failed), runs: [])

            #expect(lines == ["Not collected: failed, outskirts scan (roots) exited 1: boom."])
        }
    }
}
