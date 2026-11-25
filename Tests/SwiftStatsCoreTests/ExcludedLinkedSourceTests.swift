//
//  ExcludedLinkedSourceTests.swift
//  SwiftStatsCoreTests
//
//  A source the scan doesn't parse (a `.swiftstats.yml` glob excludes it)
//  in a target directory that is a symbolic link (M7, `SourcePaths`). The
//  tools give its real path, which the manifest never names; the unit
//  filter spells its unit as the describe does, so the build output and
//  outskirts must too: the scanned files first, then the describe's other
//  sources, and an unscanned file in a linked test directory is still in
//  that test target's directory.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Excluded sources in linked directories across the T1 readers.
@Suite("Excluded sources in linked directories")
struct ExcludedLinkedSourceTests {
    /// The excluded-source package: `Lib` at `Sources/Lib`, a link to
    /// `Real/Lib`, and `LibTests` at `Tests/LibTests`, a link to
    /// `RealTests/LibTests`, each with one source `.swiftstats.yml`
    /// excludes from the scan.
    private static func excludedLinked() throws -> LinkedPackage {
        try LinkedPackage(
            files: [
                "Real/Lib/Lib.swift": "public func one() -> Int {\n    1\n}\n",
                "Real/Lib/Excluded.swift": "func excludedHelper() -> Int {\n    4\n}\n",
                "RealTests/LibTests/LibTests.swift": "func probe() {}\n",
                "RealTests/LibTests/Skipped.swift": "func skipped() {}\n"
            ],
            links: ["Sources/Lib": "../Real/Lib", "Tests/LibTests": "../RealTests/LibTests"],
            targets: [
                DescribedTarget(
                    name: "Lib",
                    type: "library",
                    moduleType: "SwiftTarget",
                    path: "Sources/Lib",
                    sources: ["Excluded.swift", "Lib.swift"]
                ),
                DescribedTarget(
                    name: "LibTests",
                    type: "test",
                    moduleType: "SwiftTarget",
                    path: "Tests/LibTests",
                    sources: ["LibTests.swift", "Skipped.swift"]
                )
            ],
            excluded: ["Sources/Lib/Excluded.swift", "Tests/LibTests/Skipped.swift"]
        )
    }

    @Test("a source the scan excludes, in a linked directory, keeps its manifest spelling in every reader")
    func excludedLinkedSource() throws {
        let probe = try Self.excludedLinked()
        defer { probe.remove() }
        let excluded = "Sources/Lib/Excluded.swift"
        let skipped = "Tests/LibTests/Skipped.swift"
        #expect(probe.measured.files.map(\.path).sorted() == ["Sources/Lib/Lib.swift", "Tests/LibTests/LibTests.swift"])
        #expect(probe.real(excluded) == probe.root + "/Real/Lib/Excluded.swift")

        let paths = SourcePaths(root: probe.root, files: probe.measured.files, package: probe.described)
        #expect(paths.packagePath(of: probe.real(excluded), in: nil) == excluded)
        #expect(paths.packagePath(of: probe.real("Sources/Lib/Lib.swift"), in: nil) == "Sources/Lib/Lib.swift")
        let mapper = TimingMapper(measured: probe.measured, paths: paths, build: probe.build, changedFiles: [])
        #expect(mapper.place(probe.timing(excluded, line: 1, column: 6)) == .unscanned(excluded))
        let reader = WarningReader(
            measured: probe.measured,
            targets: probe.targets,
            paths: paths,
            build: probe.build,
            changedFiles: []
        )
        #expect(reader.read([probe.warning(excluded, line: 2, column: 5)]).findings.first?.places.first?.file
            == excluded)

        // No `modules`, so only the test directory can make the skipped
        // test file test code.
        let objects: [[String: Any]] = [(excluded, ["Lib"]), (skipped, [])].map { path, modules in
            [
                "accessibility": "internal", "attributes": [String](), "hints": ["unused"], "ids": ["s:probe"],
                "kind": "function.free", "location": probe.real(path) + ":1:6",
                "modifiers": [String](), "modules": modules, "name": "f()"
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: objects)
        let entries = try PeripheryOutput.decode(data, run: .production, context: try probe.peripheryContext())
        #expect(entries.map(\.file) == [excluded, skipped])
        #expect(entries.map(\.entryClass) == [.unscanned, .test])
    }
}
