//
//  UnitFilterPathTests.swift
//  SwiftStatsCoreTests
//
//  `UnitFilter` (M7, design §2.3) on describe paths the Index fixture
//  doesn't have: a target at the package root (`path: "."`) and a source
//  that isn't a clean path, which must match the unit's main file as
//  `TargetResolver` joins them, and a local path dependency nested in the
//  root, whose units are another package's and stay in the store.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The unit filter's handling of describe paths and local dependencies.
@Suite("Unit filter paths")
struct UnitFilterPathTests {
    /// A temporary package root holding empty files.
    private struct Root {
        /// The root's real path.
        let path: String

        /// The scratch folder's real path.
        var build: String {
            path + "/.swiftstats/index-build"
        }

        /// A fresh root holding an empty file at each of `files` (paths
        /// in the package).
        init(files: [String]) throws {
            let manager = FileManager.default
            let url = manager.temporaryDirectory.appendingPathComponent("UnitFilterPathTests-\(UUID().uuidString)")
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            path = WorkCopyHarness.realPath(url)
            for file in files {
                let fileURL = URL(fileURLWithPath: path).appendingPathComponent(file)
                try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: fileURL)
            }
        }

        /// A filter for the root with `package`.
        func filter(_ package: DescribedPackage) throws -> UnitFilter {
            try UnitFilter(root: path, scratch: build, package: package)
        }

        /// A unit named `name` of `module` whose main file is `file` (a
        /// path in the package).
        func unit(_ name: String, module: String, file: String) -> IndexUnitFact {
            IndexUnitFact(
                name: name,
                module: module,
                mainFile: path + "/" + file,
                target: "arm64-apple-macos14.0",
                isSystem: false,
                modified: IndexUnitFact.ModificationDate(seconds: 1, nanoseconds: 0),
                records: [],
                moduleDependencies: []
            )
        }
    }

    /// A one-target package whose target `name` is at `path` with
    /// `sources`, depending on `dependencies`.
    private static func package(
        target name: String,
        path: String,
        sources: [String],
        dependencies: [DescribedDependency]
    ) -> DescribedPackage {
        DescribedPackage(
            name: "Probe",
            targets: [
                DescribedTarget(name: name, type: "executable", moduleType: "SwiftTarget", path: path, sources: sources)
            ],
            dependencies: dependencies
        )
    }

    @Test("a target at the package root and a source with . and .. segments match their units' main files")
    func rootTarget() throws {
        let root = try Root(files: ["main.swift", "Util.swift"])
        let filter = try root.filter(Self.package(
            target: "Tool",
            path: ".",
            sources: ["main.swift", "./Sub/../Util.swift"],
            dependencies: []
        ))
        let units = [
            root.unit("main.o-1", module: "Tool", file: "main.swift"),
            root.unit("Util.o-1", module: "Tool", file: "Util.swift")
        ]

        #expect(filter.classify(units).map(\.unitClass) == [.kept, .kept])
    }

    @Test("units of a local path dependency nested in the root are another package's and the quarantine leaves them")
    func nestedDependency() throws {
        let dependencyFile = "LocalPackages/Foo/Sources/Foo/Foo.swift"
        let root = try Root(files: ["Sources/App/App.swift", dependencyFile])
        let absolute = DescribedDependency(
            identity: "foo",
            type: "fileSystem",
            location: root.path + "/LocalPackages/Foo",
            requirement: nil
        )
        let relative = DescribedDependency(
            identity: "foo",
            type: "fileSystem",
            location: "LocalPackages/./Foo",
            requirement: nil
        )
        let units = [
            root.unit("App.o-1", module: "App", file: "Sources/App/App.swift"),
            root.unit("Foo.o-1", module: "Foo", file: dependencyFile)
        ]
        let store = root.build + "/" + BuildSession.storeDirectory + "/" + BuildSession.unitsPath
        try FileManager.default.createDirectory(atPath: store, withIntermediateDirectories: true)
        for unit in units {
            try Data().write(to: URL(fileURLWithPath: store + "/" + unit.name))
        }

        for dependency in [absolute, relative] {
            let filter = try root.filter(Self.package(
                target: "App",
                path: "Sources/App",
                sources: ["App.swift"],
                dependencies: [dependency]
            ))
            let classed = filter.classify(units)

            #expect(classed.map(\.unitClass) == [.kept, .otherPackage])
            #expect(try filter.quarantine(classed).isEmpty)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store).sorted() == ["App.o-1", "Foo.o-1"])
    }
}
