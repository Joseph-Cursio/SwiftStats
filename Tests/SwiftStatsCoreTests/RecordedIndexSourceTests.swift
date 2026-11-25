//
//  RecordedIndexSourceTests.swift
//  SwiftStatsCoreTests
//
//  `RecordedIndexSource` (M7, design §2.2): the Index fixture's recorded
//  dumps decode into the reader's values, with their paths put back.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The recorded reader output, read through `RecordedIndexSource`.
@Suite("Recorded index source")
struct RecordedIndexSourceTests {
    /// Paths for the placeholders, shaped as a run's.
    private static let paths = [
        IndexFixture.rootToken: "/run/work/Index",
        IndexFixture.buildToken: "/run/work/Index/.swiftstats/index-build",
        IndexFixture.dependencyToken: "/run/work/IndexDep"
    ]

    /// The fixture's first-build dump with `paths` put back.
    private static func fresh() throws -> RecordedIndexSource {
        try RecordedIndexSource(recording: IndexFixture.data("reader.json"), restoring: paths)
    }

    @Test("the first build's dump decodes with every non-system unit and the records of the units under the root")
    func decodes() throws {
        let source = try Self.fresh()
        let names = source.unitNames()
        let occurrences = source.records.values.reduce(0) { $0 + $1.occurrences.count }
        let underRoot = names.compactMap { name in source.units[name] }
            .filter { $0.mainFile.hasPrefix("/run/work/Index/") }

        #expect(names.count == 26)
        #expect(names == names.sorted())
        #expect(source.records.count == 24)
        #expect(occurrences == 1_308)
        #expect(source.units.values.allSatisfy { $0.isSystem == false })
        #expect(Set(underRoot.flatMap(\.records)) == Set(source.records.keys))
    }

    @Test("the stale case's dump decodes with the renamed file's unit and both units of the moved file")
    func decodesStale() throws {
        let source = try RecordedIndexSource(recording: IndexFixture.data("reader-stale.json"), restoring: Self.paths)
        let relays = source.units.values.filter { $0.mainFile.hasSuffix("/Sources/Kits/Relay.swift") }

        #expect(source.unitNames().count == 28)
        #expect(source.records.count == 26)
        #expect(source.units["Formatting.o-2O0IO76AFY1BN"] != nil)
        #expect(source.units["LineFormatting.o-G6KAE1AVKNE3"] != nil)
        #expect(Set(relays.map(\.module)) == ["index_kit", "index_support"])
    }

    @Test("a unit reads its module, main file, triple, date, records and module dependencies as recorded")
    func unitFields() throws {
        let unit = try Self.fresh().unit(named: "IndexCoreTests.o-X94YURMHJFQO")

        #expect(unit.module == "IndexCoreTests")
        #expect(unit.mainFile == "/run/work/Index/Tests/IndexCoreTests/IndexCoreTests.swift")
        #expect(unit.target == "arm64-apple-macos14.0")
        #expect(unit.modified == IndexUnitFact.ModificationDate(seconds: 1_795_607_287, nanoseconds: 651_432_637))
        #expect(unit.records == ["IndexCoreTests.swift-PTEX7T57Z9VP"])
        #expect(unit.moduleDependencies.filter { $0.isSystem == false }.map(\.module) == [
            "IndexCore", "index_kit", "index_support"
        ])
        #expect(unit.moduleDependencies.count { $0.module == "Swift" } == 3)
    }

    @Test("a record reads its file and occurrences with their relations as recorded")
    func recordFields() throws {
        let record = try Self.fresh().record(named: "Accessors.swift-8ROXMIAYDKZA")
        let getter = try #require(record.occurrences.first { $0.name == "getter:values" })

        #expect(record.file == "/run/work/Index/Sources/IndexCore/Accessors.swift")
        #expect(record.occurrences.count == 159)
        #expect(getter.line == 4)
        #expect(getter.column == 9)
        #expect(getter.usr == "s:9IndexCore7StorageV6valuesSaySiGvg")
        #expect(getter.relations.map(\.usr) == ["s:9IndexCore7StorageV6valuesSaySiGvp"])
        #expect(getter.relations.first?.roles == IndexSymbolKind.RelationRole.accessorOf
            | IndexSymbolKind.RelationRole.childOf)
    }

    @Test("placeholders are put back where a main file or record file starts with one, and nowhere else")
    func restoresPlaceholders() throws {
        let source = try Self.fresh()
        let recording = Data("""
            {"units":[{"name":"A.o-1","module":"A","mainFile":"/elsewhere/@ROOT@/A.swift","target":"t",\
            "isSystem":false,"modified":{"seconds":1,"nanoseconds":2},"records":["A.swift-1"],\
            "moduleDependencies":[]},{"name":"B.o-1","module":"B","mainFile":"@ROOT@","target":"t",\
            "isSystem":false,"modified":{"seconds":1,"nanoseconds":2},"records":[],"moduleDependencies":[]},\
            {"name":"C.o-1","module":"C","mainFile":"@ROOTED@/C.swift","target":"t",\
            "isSystem":false,"modified":{"seconds":1,"nanoseconds":2},"records":[],"moduleDependencies":[]}],\
            "records":[{"name":"A.swift-1","file":"@BUILD@/A.swift","otherFiles":["@BUILD@/B.swift"],\
            "occurrences":[]}]}
            """.utf8)
        let synthetic = try RecordedIndexSource(recording: recording, restoring: Self.paths)

        #expect(try source.unit(named: "DepKit.o-3QG4QQUHJ0YQ0").mainFile
            == "/run/work/IndexDep/Sources/IndexDepKit/DepKit.swift")
        #expect(try source.unit(named: "test_entry_point.o-27JSI56QYPVCU").mainFile.hasPrefix(
            "/run/work/Index/.swiftstats/index-build/out/Intermediates.noindex/"
        ))
        #expect(source.units.values.allSatisfy { $0.mainFile.hasPrefix("/run/work/") })
        #expect(source.records.values.allSatisfy { $0.file.hasPrefix("/run/work/Index/") })
        #expect(try synthetic.unit(named: "A.o-1").mainFile == "/elsewhere/@ROOT@/A.swift")
        #expect(try synthetic.unit(named: "B.o-1").mainFile == "/run/work/Index")
        #expect(try synthetic.unit(named: "C.o-1").mainFile == "@ROOTED@/C.swift")
        #expect(try synthetic.record(named: "A.swift-1").file == "/run/work/Index/.swiftstats/index-build/A.swift")
    }

    @Test("a unit or record the recording lacks fails, naming it; IndexDep's records aren't recorded")
    func missing() throws {
        let source = try Self.fresh()
        let dependency = try source.unit(named: "DepKit.o-3QG4QQUHJ0YQ0")

        #expect(dependency.records == ["DepKit.swift-2MJKIK49E5DSA"])
        #expect {
            _ = try source.record(named: "DepKit.swift-2MJKIK49E5DSA")
        } throws: { error in
            String(describing: error) == "the recording holds no record DepKit.swift-2MJKIK49E5DSA"
        }
        #expect {
            _ = try source.unit(named: "Gone.o-1")
        } throws: { error in
            String(describing: error) == "the recording holds no unit Gone.o-1"
        }
    }
}
