import Foundation
@testable import SwiftStatsCore
import Testing

/// Why a record has no USR, and the join's disagreements (M7, design §3.4,
/// §3.5): the first reason that applies, in order, and each reason on the
/// Index fixture's recorded index with an input changed to call for it: a
/// file edited during the build, a unit or a target's units taken out, a
/// target made a plugin, the build's log without a target's compile, a
/// definition given a second USR or another record's, and a unit of
/// another triple.
/// Serialized, and each scan runs on a thread of its own: a test holding a
/// pool thread for seconds starves `BlockingAsyncTests`' detached tasks.
@Suite("USR reasons", .serialized)
struct USRReasonTests {
    /// The index record of `key` in `outcome`'s scan.
    private static func record(_ key: String, in outcome: IndexGroupHarness.Outcome) throws -> IndexRecordUSR {
        let index = try #require(outcome.report.index)
        return try #require(index.records.first { $0.key == key }, "\(key)")
    }

    /// `source` with the units whose names start with one of `prefixes`
    /// taken out.
    private static func without(_ prefixes: [String], in source: RecordedIndexSource) -> RecordedIndexSource {
        RecordedIndexSource(
            units: source.units.values.filter { unit in prefixes.contains { unit.name.hasPrefix($0) } == false },
            records: Array(source.records.values)
        )
    }

    /// `occurrence` with `usr` as its symbol's USR.
    private static func renamed(_ occurrence: IndexOccurrenceFact, to usr: String) -> IndexOccurrenceFact {
        IndexOccurrenceFact(
            line: occurrence.line,
            column: occurrence.column,
            roles: occurrence.roles,
            usr: usr,
            name: occurrence.name,
            kind: occurrence.kind,
            subkind: occurrence.subkind,
            properties: occurrence.properties,
            relations: occurrence.relations
        )
    }

    /// Evidence for `record` in which every reason after top-level code
    /// applies; `record` is under `#if` in module `IndexCore`.
    private static func evidence(
        for record: FunctionRecord,
        plugin: Bool,
        definitionInside: Bool,
        changed: Bool,
        unitModule: Bool
    ) -> USRReason.Evidence {
        USRReason.Evidence(
            pluginTargets: plugin ? [record.module] : [],
            changedFiles: changed ? [record.file] : [],
            definitions: definitionInside ? [record.file: [record.range.start]] : [:],
            unitModules: unitModule ? [record.module] : [],
            readFiles: unitModule ? [record.module: ["Sources/IndexCore/Other.swift"]] : [:],
            inDisagreement: [record.key]
        ) { _ in false }
    }

    @Test("""
        the first reason that applies wins: top-level code, plugin target, inactive #if branch, file changed, \
        target not built, file not indexed, disagreement, unexplained
        """)
    func firstReasonWins() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let records = fixture.measured.records
        let flagged = try #require(records.first { $0.ifConfig?.contains("INDEX_FIXTURE_FLAG") == true })
        let topLevel = try #require(records.first { $0.kind == .topLevelCode })
        let all = Self.evidence(for: topLevel, plugin: true, definitionInside: false, changed: true, unitModule: false)
        #expect(USRReason.first(for: topLevel, evidence: all) == .topLevelCode)

        func reason(plugin: Bool, inside: Bool, changed: Bool, unit: Bool) -> USRReason {
            USRReason.first(
                for: flagged,
                evidence: Self.evidence(
                    for: flagged,
                    plugin: plugin,
                    definitionInside: inside,
                    changed: changed,
                    unitModule: unit
                )
            )
        }
        #expect(reason(plugin: true, inside: false, changed: true, unit: false) == .pluginTarget)
        #expect(reason(plugin: false, inside: false, changed: true, unit: false) == .inactiveIfBranch)
        #expect(reason(plugin: false, inside: true, changed: true, unit: false) == .fileChanged)
        #expect(reason(plugin: false, inside: true, changed: false, unit: false) == .targetNotBuilt)
        #expect(reason(plugin: false, inside: true, changed: false, unit: true) == .fileNotIndexed)

        var known = Self.evidence(for: flagged, plugin: false, definitionInside: true, changed: false, unitModule: true)
        known = USRReason.Evidence(
            pluginTargets: [],
            changedFiles: [],
            definitions: known.definitions,
            unitModules: known.unitModules,
            readFiles: [flagged.module: [flagged.file]],
            inDisagreement: [flagged.key]
        ) { _ in false }
        #expect(USRReason.first(for: flagged, evidence: known) == .disagreement)
        let settled = USRReason.Evidence(
            pluginTargets: [],
            changedFiles: [],
            definitions: known.definitions,
            unitModules: [],
            readFiles: [:],
            inDisagreement: []
        ) { $0 == flagged.module }
        #expect(USRReason.first(for: flagged, evidence: settled) == .unexplained)
    }

    @Test("""
        a file edited during the build is not joined, its records reading file changed, while its inactive \
        #if records stay inactive, and its hash after the build is listed
        """)
    func fileChanged() async throws {
        var scan = try IndexFixtureScan()
        scan.scenario.edits = ["Sources/IndexCore/TestOnly.swift"]
        try await scan.run { fixture, outcome in
            let index = try #require(outcome.report.index)
            let file = "Sources/IndexCore/TestOnly.swift"
            let inFile = Set(fixture.measured.records.filter { $0.file == file }.map(\.key))
            let reasons = index.records.filter { inFile.contains($0.key) }
            #expect(reasons.count == 7)
            #expect(reasons.allSatisfy { $0.usr == nil })
            #expect(reasons.count { $0.reason == .inactiveIfBranch } == 2)
            #expect(reasons.count { $0.reason == .fileChanged } == 5)
            let parsed = try #require(fixture.measured.files.first { $0.path == "Sources/IndexCore/TestOnly.swift" })
            let hashed = try #require(index.files.first { $0.path == parsed.path })
            #expect(hashed.sha256 != nil && hashed.sha256 != parsed.sha256)
            #expect(index.records.count { $0.usr != nil } == 97 - 5)
        }
    }

    @Test("a file whose target has units read but none for it is not indexed")
    func fileNotIndexed() async throws {
        var scan = try IndexFixtureScan()
        scan.source = { Self.without(["Bom.o-"], in: $0) }
        try await scan.run { _, outcome in
            let first = try Self.record("IndexCore::func bomFirst() -> Int", in: outcome)
            let second = try Self.record("IndexCore::func bomSecond() -> Int", in: outcome)
            #expect(first.reason == .fileNotIndexed && second.reason == .fileNotIndexed)
            #expect(outcome.report.index?.store.counts.kept == 21)
        }
    }

    @Test("""
        a target no unit names is not built only when the build's log names no compile of it, and its records \
        are unexplained when the log does
        """)
    func targetNotBuilt() async throws {
        let keys = ["index-kit::func kitOnlyTests() -> Int", "index-kit::func relay() -> Int"]
        var scan = try IndexFixtureScan()
        scan.source = { Self.without(["Kit.o-", "Relay.o-"], in: $0) }
        try await scan.run { _, outcome in
            for key in keys {
                let record = try Self.record(key, in: outcome)
                #expect(record.reason == .unexplained)
            }
        }
        scan.scenario.stdout = scan.scenario.stdout.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("-module-name index_kit") == false }
            .joined(separator: "\n")
        try await scan.run { _, outcome in
            for key in keys {
                let record = try Self.record(key, in: outcome)
                #expect(record.reason == .targetNotBuilt)
            }
            let kit = try #require(outcome.report.rollups.first { $0.name == "index-kit" }?.index)
            #expect(kit.withUSR == 0 && kit.withoutUSR["targetNotBuilt"] == 2)
        }
    }

    @Test("a plugin target's records, which the build never indexes, read plugin target")
    func pluginTarget() async throws {
        var scan = try IndexFixtureScan()
        scan.scenario.describe = scan.scenario.describe.replacingOccurrences(
            of: "\"sources\" : [\n        \"Support.swift\"\n      ],\n      \"type\" : \"library\"",
            with: "\"sources\" : [\n        \"Support.swift\"\n      ],\n      \"type\" : \"plugin\""
        )
        scan.source = { Self.without(["Support.o-"], in: $0) }
        try await scan.run { _, outcome in
            let index = try #require(outcome.report.index)
            let support = index.records.filter { $0.key.hasPrefix("index-support::") }
            #expect(support.count == 4)
            #expect(support.allSatisfy { $0.usr == nil && $0.reason == .pluginTarget })
        }
    }

    @Test("""
        a record with two distinct USRs and two pairs of records sharing one each keep none, reading \
        disagreement, and are listed with their USRs and definitions' places, each kind by key, then USR
        """)
    func disagreements() async throws {
        var scan = try IndexFixtureScan()
        scan.source = { source in
            let records = source.records.values.map { record -> IndexRecordFact in
                guard record.file.hasSuffix("/Sources/IndexCore/TestOnly.swift") else {
                    return record
                }
                var occurrences: [IndexOccurrenceFact] = []
                for occurrence in record.occurrences {
                    let isDefinition = occurrence.roles & IndexSymbolKind.Role.definition != 0
                    if isDefinition, occurrence.usr == "s:9IndexCore5casesSaySiGyF" {
                        occurrences.append(Self.renamed(occurrence, to: "s:9IndexCore13onlyTestsCallSiyF"))
                    } else if isDefinition, occurrence.usr == "s:9IndexCore15publicOnlyTestsSiyF" {
                        occurrences.append(Self.renamed(occurrence, to: "s:9IndexCore11neverCalledSiyF"))
                    } else {
                        occurrences.append(occurrence)
                    }
                    if isDefinition, occurrence.usr == "s:9IndexCore11neverCalledSiyF" {
                        occurrences.append(Self.renamed(occurrence, to: "s:9IndexCore5otherSiyF"))
                    }
                }
                return IndexRecordFact(name: record.name, file: record.file, occurrences: occurrences)
            }
            return RecordedIndexSource(units: Array(source.units.values), records: records)
        }
        try await scan.run { _, outcome in
            let index = try #require(outcome.report.index)
            let keys = [
                "IndexCore::func cases() -> [Int]", "IndexCore::func neverCalled() -> Int",
                "IndexCore::func onlyTestsCall() -> Int", "IndexCore::func publicOnlyTests() -> Int"
            ]
            for key in keys {
                let record = try Self.record(key, in: outcome)
                #expect(record.usr == nil && record.reason == .disagreement, "\(key)")
            }
            #expect(index.disagreements.map { [$0.kind.rawValue, $0.key ?? "", $0.usr ?? ""] } == [
                ["severalUSRs", keys[1], "s:9IndexCore11neverCalledSiyF"],
                ["severalUSRs", keys[1], "s:9IndexCore5otherSiyF"],
                ["sharedUSR", keys[0], "s:9IndexCore13onlyTestsCallSiyF"],
                ["sharedUSR", keys[1], "s:9IndexCore11neverCalledSiyF"],
                ["sharedUSR", keys[2], "s:9IndexCore13onlyTestsCallSiyF"],
                ["sharedUSR", keys[3], "s:9IndexCore11neverCalledSiyF"]
            ])
            #expect(index.disagreements.allSatisfy { $0.file == "Sources/IndexCore/TestOnly.swift" })
            let several = index.disagreements.filter { $0.kind == .severalUSRs }
            #expect(several.count == 2 && several[0].line == several[1].line && several[0].column == several[1].column)
            let core = try #require(outcome.report.rollups.first { $0.name == "IndexCore" }?.index)
            #expect(core.disagreements == 4 && core.withoutUSR["disagreement"] == 4)
        }
    }

    @Test("""
        a unit of another triple for the same file makes both units variants, read once each, its records \
        keeping one USR each with no disagreement, and a definition met through a variant's own record counts \
        once: no doubled listing, getter or count
        """)
    func variants() async throws {
        var scan = try IndexFixtureScan()
        // Bom's variant names Bom's record; Protocols' and Accessors' name
        // copies of theirs, the same definitions under another record name.
        scan.source = { source in
            source.addingVariants(of: ["Bom", "Protocols", "Accessors"], ownRecords: ["Protocols", "Accessors"])
        }
        try await scan.run { _, outcome in
            let index = try #require(outcome.report.index)
            #expect(index.store.counts.variant == 6 && index.store.counts.kept == 19)
            #expect(index.store.units.filter { $0.unitClass == .variant }.map(\.name).sorted() == [
                "Accessors.o-1Z3K8JGC10BSA", "Accessors.o-VARIANT", "Bom.o-24GNIJHMVBKMD", "Bom.o-VARIANT",
                "Protocols.o-2G747Z8I420W1", "Protocols.o-VARIANT"
            ])
            #expect(index.store.records == 24)
            #expect(index.disagreements.isEmpty)
            let bom = try Self.record("IndexCore::func bomFirst() -> Int", in: outcome)
            #expect(bom.usr == "s:9IndexCore8bomFirstSiyF")
            let storage = try Self.record("IndexCore::Storage::subscript(_: Int) -> Int", in: outcome)
            #expect(storage.usrAccessor == "s:9IndexCore7StorageVyS2icig")
            #expect(index.definitions == IndexDefinitions(joined: 99, implicit: 120, secondary: 2, objc: 1))
            #expect(index.withoutRecord.map { $0.usr ?? "" } == [
                "s:9IndexCore5ShapeP4areaSiyF", "s:9IndexCore7GreeterP5greetSSyF"
            ])
        }
    }
}
