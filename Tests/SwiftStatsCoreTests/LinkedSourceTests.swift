//
//  LinkedSourceTests.swift
//  SwiftStatsCoreTests
//
//  Sources reached through symbolic links or spelled in another case than
//  the disk (M7, `SourcePaths`). The compiler, the index store and
//  outskirts give real paths; the scan and the describe keep the
//  package's spelling. A target directory that is a link, a file linked to
//  one outside `Sources/` and a file linked to one outside the root must
//  each get its timings, warnings, kept units, USR-join paths and outskirts
//  entries under the scan's spelling, and so must a target whose manifest
//  path differs in case on a case-insensitive volume.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Linked and case-mismatched sources across the T1 readers.
@Suite("Linked and case-mismatched sources")
struct LinkedSourceTests {
    /// An index store source holding `units` and `records`.
    private struct FixedSource: IndexStoreSource {
        /// The units.
        let units: [IndexUnitFact]
        /// The records.
        let records: [IndexRecordFact]

        /// Every unit's name, in code point order.
        func unitNames() -> [String] {
            Self.codePointSorted(units.map(\.name))
        }

        /// The unit named `name`.
        func unit(named name: String) throws -> IndexUnitFact {
            try #require(units.first { $0.name == name })
        }

        /// The record named `name`.
        func record(named name: String) throws -> IndexRecordFact {
            try #require(records.first { $0.name == name })
        }
    }

    /// Whether the temporary directory's volume compares names without
    /// case, as a default APFS volume does.
    private static let caseInsensitiveVolume: Bool = {
        let values = try? FileManager.default.temporaryDirectory
            .resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values?.volumeSupportsCaseSensitiveNames == false
    }()

    /// A library's one function.
    private static let library = "public func one() -> Int {\n    1\n}\n"
    /// A tool's one function.
    private static let tool = "func helper() -> Int {\n    2\n}\n"

    /// The linked package's sources: path in the package, module, and the
    /// function's line and name column.
    private static let linkedSources = [
        ("Sources/Lib/Lib.swift", "Lib", "Lib::func one() -> Int", 13),
        ("Sources/Tool/Far.swift", "Tool", "Tool::func distant() -> Int", 6),
        ("Sources/Tool/Tool.swift", "Tool", "Tool::func helper() -> Int", 6)
    ]

    /// The linked package: `Lib` at `Sources/Lib`, a link to `Real/Lib`;
    /// `Tool` with `Tool.swift`, a link to `Shared/Tool.swift`, and
    /// `Far.swift`, a link to a file outside the root.
    private static func linked() throws -> LinkedPackage {
        try LinkedPackage(
            files: ["Real/Lib/Lib.swift": library, "Shared/Tool.swift": tool],
            links: [
                "Sources/Lib": "../Real/Lib",
                "Sources/Tool/Tool.swift": "../../Shared/Tool.swift",
                "Sources/Tool/Far.swift": "@OUTSIDE@/Far.swift"
            ],
            targets: [
                DescribedTarget(
                    name: "Lib",
                    type: "library",
                    moduleType: "SwiftTarget",
                    path: "Sources/Lib",
                    sources: ["Lib.swift"]
                ),
                DescribedTarget(
                    name: "Tool",
                    type: "executable",
                    moduleType: "SwiftTarget",
                    path: "Sources/Tool",
                    sources: ["Far.swift", "Tool.swift"]
                )
            ]
        )
    }

    /// The case-mismatched package: `Lib`'s manifest path is
    /// `sources/lib`, the disk's `Sources/Lib`.
    private static func caseMismatched() throws -> LinkedPackage {
        try LinkedPackage(
            files: ["Sources/Lib/Lib.swift": library],
            links: [:],
            targets: [
                DescribedTarget(
                    name: "Lib",
                    type: "library",
                    moduleType: "SwiftTarget",
                    path: "sources/lib",
                    sources: ["Lib.swift"]
                )
            ]
        )
    }

    @Test("timings and warnings at a linked source's real path go to the scanned file")
    func linkedTimingsAndWarnings() throws {
        let probe = try Self.linked()
        defer { probe.remove() }
        #expect(probe.measured.files.map(\.path).sorted() == Self.linkedSources.map(\.0))
        let mapper = TimingMapper(measured: probe.measured, root: probe.root, build: probe.build, changedFiles: [])
        let entries = Self.linkedSources.map { probe.timing($0.0, line: 1, column: $0.3) }

        #expect(entries.map(mapper.place) == Self.linkedSources.map { .record($0.2) })
        let mapped = mapper.map(entries)
        #expect(mapped.records.map(\.key) == Self.linkedSources.map(\.2))
        #expect(mapped.dropped.unscanned.entries == 0 && mapped.dropped.outsideRoot.entries == 0)

        let reader = WarningReader(
            measured: probe.measured,
            targets: probe.targets,
            root: probe.root,
            build: probe.build,
            changedFiles: []
        )
        let read = reader.read(Self.linkedSources.map { probe.warning($0.0, line: 2, column: 5) })
        #expect(read.findings.compactMap(\.places.first?.file) == Self.linkedSources.map(\.0))
        #expect(read.dropped == 0)
    }

    @Test("a linked source's unit is kept, nothing is quarantined, and its main file and records read as scanned")
    func linkedUnits() throws {
        let probe = try Self.linked()
        defer { probe.remove() }
        let units = Self.linkedSources.enumerated().map { offset, source in
            probe.unit("U\(offset).o", module: source.1, path: source.0, record: "R\(offset)")
        }
        let records = Self.linkedSources.enumerated().map { offset, source in
            IndexRecordFact(name: "R\(offset)", file: probe.real(source.0), occurrences: [])
        }
        let store = probe.build + "/" + BuildSession.storeDirectory + "/" + BuildSession.unitsPath
        try FileManager.default.createDirectory(atPath: store, withIntermediateDirectories: true)
        for unit in units {
            try Data().write(to: URL(fileURLWithPath: store + "/" + unit.name))
        }
        let filter = try UnitFilter(root: probe.root, scratch: probe.build, package: probe.described)

        #expect(filter.classify(units).map(\.unitClass) == [.kept, .kept, .kept])
        let snapshot = try IndexWalk.walk(FixedSource(units: units, records: records), filter: filter)
        #expect(snapshot.units.map(\.path) == Self.linkedSources.map(\.0))
        #expect(snapshot.records.map(\.path) == Self.linkedSources.map(\.0))
        #expect(try filter.quarantine(snapshot).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store).sorted() == units.map(\.name))
        let occurrences = USRJoin.occurrences(in: snapshot)
        #expect(Set(occurrences.keys) == Set(Self.linkedSources.map(\.0)))
    }

    @Test("an outskirts entry at a linked source's real path is the scanned file's production code")
    func linkedPeriphery() throws {
        let probe = try Self.linked()
        defer { probe.remove() }
        let objects: [[String: Any]] = Self.linkedSources.map { source in
            [
                "accessibility": "internal", "attributes": [String](), "hints": ["unused"], "ids": ["s:probe"],
                "kind": "function.free", "location": probe.real(source.0) + ":1:\(source.3)",
                "modifiers": [String](), "modules": [source.1], "name": "f()"
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: objects)
        let entries = try PeripheryOutput.decode(data, run: .production, context: try probe.peripheryContext())

        #expect(entries.map(\.file) == Self.linkedSources.map(\.0))
        #expect(entries.allSatisfy { $0.entryClass == .production })
    }

    @Test(
        "a target path in another case than the disk's matches its unit, timings, warnings and outskirts entries",
        .enabled(if: caseInsensitiveVolume)
    )
    func caseMismatch() throws {
        let probe = try Self.caseMismatched()
        defer { probe.remove() }
        let spelled = "sources/lib/Lib.swift"
        let onDisk = "Sources/Lib/Lib.swift"
        #expect(probe.measured.files.map(\.path) == [spelled])
        #expect(probe.real(spelled) == probe.root + "/" + onDisk)

        let filter = try UnitFilter(root: probe.root, scratch: probe.build, package: probe.described)
        let unit = probe.unit("Lib.o", module: "Lib", path: onDisk, record: "R")
        #expect(filter.classify([unit]).map(\.unitClass) == [.kept])
        #expect(filter.packagePath(of: unit.mainFile, module: "Lib") == spelled)

        let mapper = TimingMapper(measured: probe.measured, root: probe.root, build: probe.build, changedFiles: [])
        #expect(mapper.place(probe.timing(onDisk, line: 1, column: 13)) == .record("Lib::func one() -> Int"))

        let reader = WarningReader(
            measured: probe.measured,
            targets: probe.targets,
            root: probe.root,
            build: probe.build,
            changedFiles: []
        )
        #expect(reader.read([probe.warning(onDisk, line: 2, column: 5)]).findings.first?.places.first?.file == spelled)

        let object: [String: Any] = [
            "accessibility": "public", "attributes": [String](), "hints": ["unused"], "ids": ["s:probe"],
            "kind": "function.free", "location": probe.real(onDisk) + ":1:13", "modifiers": [String](),
            "modules": ["Lib"], "name": "one()"
        ]
        let data = try JSONSerialization.data(withJSONObject: [object])
        let entries = try PeripheryOutput.decode(data, run: .production, context: try probe.peripheryContext())
        #expect(entries.map(\.file) == [spelled])
        #expect(entries.map(\.entryClass) == [.production])
    }
}
