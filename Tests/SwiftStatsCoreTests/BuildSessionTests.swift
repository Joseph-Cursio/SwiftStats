import Foundation
@testable import SwiftStatsCore
import Testing

/// The T1 build's session (M7, design §1.3) against a fake toolchain: the
/// toolchain it finds, the commands it runs and their arguments, the real
/// build directory, the module map, the root package's intermediates, the
/// files it leaves, the scanned files changed during the build and the
/// index store check.
@Suite("Build session")
struct BuildSessionTests {
    /// The build's arguments after `swift`, as the fake logs them, with
    /// `<build>` for the build directory: written out, not derived, so a
    /// changed flag shows here.
    private static let buildCall = [
        "build", "--build-tests", "--build-system", "swiftbuild", "-c", "debug", "-v", "--no-color-diagnostics",
        "--scratch-path", "<build>", "-Xswiftc", "-index-include-locals",
        "-Xswiftc", "-Xfrontend", "-Xswiftc", "-debug-time-function-bodies",
        "-Xswiftc", "-Xfrontend", "-Xswiftc", "-debug-time-expression-type-checking",
        "-Xswiftc", "-Xfrontend", "-Xswiftc", "-debug-diagnostic-names"
    ].joined(separator: "\t")

    /// The first option.
    private static let invocation = "swift build --build-tests --build-system swiftbuild -c debug -v "
        + "--no-color-diagnostics --scratch-path .swiftstats/index-build -Xswiftc -index-include-locals "
        + "-Xswiftc -Xfrontend -Xswiftc -debug-time-function-bodies "
        + "-Xswiftc -Xfrontend -Xswiftc -debug-time-expression-type-checking "
        + "-Xswiftc -Xfrontend -Xswiftc -debug-diagnostic-names"

    /// The intermediates folder of the package named `name` in the build
    /// directory of the package at `root`.
    private static func intermediates(_ name: String, root: URL) -> URL {
        root.appendingPathComponent(".swiftstats/index-build/out/Intermediates.noindex/\(name).build")
    }

    @Test("""
        a passing build finds the toolchain, describes the package with the scratch path before the \
        subcommand, then builds with each flag its own argument, all by the toolchain's own swift
        """)
    func passingBuild() throws {
        try BuildHarness.run(try FakeToolchain.recordedBuild()) { outcome in
            let status = outcome.run.status
            #expect(status.state == .ran)
            #expect(status.reason == nil)
            #expect(status.version == "Apple Swift version 9.9 (fake)")
            #expect(status.options == [
                Self.invocation, "rebuild: root package intermediates", ".swift-version: absent",
                "toolchain: Apple Swift version 9.9 (fake)", "map: " + TimingMapper.rule,
                "warnings: " + WarningReader.rule
            ])
            #expect(BuildAdapter.invocation == Self.invocation)
            #expect(outcome.run.identity == "swift:Apple Swift version 9.9 (fake)")
            #expect(outcome.run.executable == outcome.toolchain.swift)
            #expect(outcome.run.warnings.isEmpty)

            // The resolved swift is asked for the target info only.
            #expect(outcome.toolchain.calls(of: "proxy") == ["-print-target-info"])
            let build = outcome.build.path
            #expect(outcome.swiftCalls == [
                "--version",
                "package\t--scratch-path\t\(build)\tdescribe\t--type\tjson",
                Self.buildCall.replacingOccurrences(of: "<build>", with: build)
            ])
            let ignore = outcome.realRoot.appendingPathComponent(".swiftstats/.gitignore")
            #expect((try? String(contentsOf: ignore, encoding: .utf8)) == "*\n")
        }
    }

    @Test("""
        a passing build keeps the description and both output streams in files in the build directory, \
        and gives the store, the module map and no changed files
        """)
    func products() throws {
        try BuildHarness.run(try FakeToolchain.recordedBuild()) { outcome in
            let products = try #require(outcome.run.products)
            let restored = { (name: String) in
                try BuildHarness.restored(
                    name,
                    toolchain: outcome.toolchain,
                    root: outcome.realRoot,
                    build: outcome.build
                )
            }
            #expect(products.scratch.path == outcome.build.path)
            #expect(products.store.path == outcome.build.appendingPathComponent("out").path)
            #expect(products.describeFile.path == outcome.build.appendingPathComponent("swiftstats-describe.json").path)
            #expect(try String(contentsOf: products.describeFile, encoding: .utf8) == restored("describe.json"))
            #expect(try String(contentsOf: products.log, encoding: .utf8) == restored("build.stdout"))
            #expect(try String(contentsOf: products.stderr, encoding: .utf8) == restored("build.stderr"))
            #expect(products.log.lastPathComponent == "swiftstats-build.log")
            #expect(products.stderr.lastPathComponent == "swiftstats-build.stderr")
            #expect(products.package.name == "IndexFixture")
            #expect(products.modules["index_kit"] == "index-kit")
            #expect(products.modules["index_support"] == "index-support")
            #expect(products.modules.count == products.package.targets.count)
            #expect(products.changedFiles.isEmpty && products.notes.isEmpty)
            #expect(products.storeFailure == nil)
            #expect(products.toolchain.swift == outcome.toolchain.swift)
        }
    }

    @Test("through a symbolic link to the package folder, every command gets the build directory's real path")
    func realBuildDirectory() throws {
        try BuildHarness.run(
            try FakeToolchain.recordedBuild(),
            linked: true,
            prepare: { _ in /* Nothing to prepare. */ },
            check: { outcome in
                let spelled = outcome.root.appendingPathComponent(".swiftstats/index-build").path
                let real = WorkCopyHarness.realPath(outcome.root.appendingPathComponent(".swiftstats/index-build"))
                #expect(spelled != real)
                #expect(outcome.run.status.state == .ran)
                #expect(outcome.run.products?.scratch.path == real)
                #expect(outcome.swiftCalls.dropFirst() == [
                    "package\t--scratch-path\t\(real)\tdescribe\t--type\tjson",
                    Self.buildCall.replacingOccurrences(of: "<build>", with: real)
                ])
                #expect(outcome.swiftCalls.allSatisfy { $0.contains(spelled) == false })
            }
        )
    }

    @Test("the module map takes each target's C99 module name to its name, dashed names included")
    func moduleMap() throws {
        let package = try JSONDecoder().decode(DescribedPackage.self, from: try IndexFixture.data("describe.json"))

        let modules = try BuildSession.moduleMap(of: package)

        #expect(modules == [
            "IndexApp": "IndexApp", "IndexCore": "IndexCore", "IndexCoreTests": "IndexCoreTests",
            "IndexTool": "IndexTool", "IndexXCTests": "IndexXCTests", "index_kit": "index-kit",
            "index_support": "index-support"
        ])
    }

    @Test("two targets sharing a C99 module name fail the build before it runs, naming both")
    func moduleClash() throws {
        let target = { (name: String) in
            DescribedTarget(
                name: name,
                type: "library",
                moduleType: "SwiftTarget",
                path: "Sources/\(name)",
                sources: []
            )
        }
        let package = DescribedPackage(name: "Clash", targets: [target("my_lib"), target("Other"), target("my-lib")])
        #expect(throws: CoverageFailure(description: "targets my-lib and my_lib share the module name my_lib")) {
            try BuildSession.moduleMap(of: package)
        }

        var scenario = try FakeToolchain.recordedBuild()
        scenario.describe = #"{"name":"Clash","targets":[{"name":"my-lib","type":"library","path":"Sources/A"},"#
            + #"{"name":"my_lib","type":"library","path":"Sources/B"}]}"#
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason == "targets my-lib and my_lib share the module name my_lib")
            #expect(outcome.built == false)
            #expect(outcome.run.products == nil)
        }
    }

    @Test("""
        the root package's intermediates, named after the manifest, are removed before the build while a \
        dependency's stay, and a first run notes nothing
        """)
    func rootIntermediates() throws {
        let plant = { (root: URL) in
            for (name, file) in [("IndexFixture", "stale.o"), ("IndexDep", "kept.o")] {
                let folder = Self.intermediates(name, root: root)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data().write(to: folder.appendingPathComponent(file))
            }
        }
        try BuildHarness.run(try FakeToolchain.recordedBuild(), prepare: plant) { outcome in
            #expect(outcome.run.status.state == .ran && outcome.run.status.reason == nil)
            let root = Self.intermediates("IndexFixture", root: outcome.realRoot)
            #expect(FileClone.exists(root))
            #expect(FileClone.exists(root.appendingPathComponent("stale.o")) == false)
            let dependency = Self.intermediates("IndexDep", root: outcome.realRoot)
            #expect(FileClone.exists(dependency.appendingPathComponent("kept.o")))
        }
        // A first run: no build directory before it.
        try BuildHarness.run(try FakeToolchain.recordedBuild()) { outcome in
            #expect(outcome.run.status.reason == nil && outcome.run.products?.notes.isEmpty == true)
        }
    }

    @Test("a build directory whose store directory holds no root intermediates notes that timings may be incomplete")
    func incompleteTimings() throws {
        let plant = { (root: URL) in
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(".swiftstats/index-build/out"),
                withIntermediateDirectories: true
            )
        }
        try BuildHarness.run(try FakeToolchain.recordedBuild(), prepare: plant) { outcome in
            let note = "timings may be incomplete: no root intermediates named IndexFixture.build to remove"
            #expect(outcome.run.status.state == .ran)
            #expect(outcome.run.status.reason == note)
            #expect(outcome.run.products?.notes == [note])
        }
    }

    @Test("a scanned file the build changes is listed, noted in the reason and named in a warning")
    func changedFile() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.edits = ["Sources/IndexCore/Formatting.swift"]
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .ran)
            #expect(outcome.run.products?.changedFiles == ["Sources/IndexCore/Formatting.swift"])
            #expect(outcome.run.status.reason == "1 file changed during the scan")
            let warning = ScanWarning(
                file: nil,
                message: "build: 1 file changed during the scan; their records get no USR, timing, warnings "
                    + "or dead-code mapping: Sources/IndexCore/Formatting.swift"
            )
            #expect(outcome.run.warnings == [warning])
        }
    }

    @Test("more than five changed files are all listed, sorted, and the warning names the first five")
    func manyChangedFiles() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.edits = BuildHarness.files.keys.sorted().reversed()
        let sorted = BuildHarness.files.keys.sorted()
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.products?.changedFiles == sorted)
            #expect(outcome.run.status.reason == "7 files changed during the scan")
            #expect(outcome.run.warnings.map(\.message) == [
                "build: 7 files changed during the scan; their records get no USR, timing, warnings or dead-code "
                    + "mapping: \(sorted.prefix(5).joined(separator: ", ")) and 2 more"
            ])
        }
    }

    @Test("a build that writes no index store runs, and the store check says why the readers can't read it")
    func noStore() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.makesStore = false
        try BuildHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .ran)
            #expect(outcome.run.products?.storeFailure == "the build wrote no index store at <build>/out")
        }
    }
}
