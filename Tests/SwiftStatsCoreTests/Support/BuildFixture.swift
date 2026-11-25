//
//  BuildFixture.swift
//  SwiftStatsCoreTests
//
//  The Index fixture copied to a temporary package and measured as a scan
//  measures it, with its recorded T1 build output read back (M7, design
//  §6, §13): the copy is described as the recorded `describe.json` lists
//  the fixture, the recording's `@ROOT@` stands for the copy's real path,
//  `@BUILD@` for its `.swiftstats/index-build` and `@DEP@` for an IndexDep
//  beside it. Nothing is built or run.
//

import Foundation
@testable import SwiftStatsCore

/// A measured copy of the Index fixture and its recorded build output.
struct BuildFixture {
    /// The environment variable that names a request for
    /// `BuildOutputExportTests`, which reads a real build's output only
    /// when it is set.
    static let exportVariable = "SWIFTSTATS_BUILD_EXPORT"

    /// The copy.
    let package: TemporaryPackage
    /// Its measurements.
    let measured: ScanMeasurements
    /// Its targets.
    let targets: [TargetSummary]
    /// The paths the recordings' placeholders stand for.
    let paths: IndexFixture.Paths

    /// The copy's root, as its real path.
    var root: String {
        paths.root
    }

    /// The copy's build directory, as its real path.
    var build: String {
        paths.build
    }

    /// A measured copy of the Index fixture; removed again if it can't be.
    init() throws {
        let describe = try IndexFixture.data("describe.json")
        let described = try JSONDecoder().decode(DescribedPackage.self, from: describe)
        let copy = try TemporaryPackage([:], targets: described.targets)
        do {
            for part in ["Sources", "Tests"] {
                try FileManager.default.copyItem(
                    at: IndexFixture.directory.appendingPathComponent(part),
                    to: copy.root.appendingPathComponent(part)
                )
            }
            let configuration = SwiftStatsConfiguration()
            targets = TargetResolver.resolve(described)
            measured = PackageScanner.measure(targets, root: copy.root, configuration: configuration)
            let realRoot = Self.realPath(copy.root)
            let parent = URL(fileURLWithPath: realRoot).deletingLastPathComponent().path
            paths = IndexFixture.Paths(
                root: realRoot,
                build: realRoot + "/.swiftstats/index-build",
                dependency: parent + "/IndexDep",
                toolchain: "/Toolchains/Fake.xctoolchain",
                temporary: parent + "/TemporaryItems",
                developer: "/Developer/Fake"
            )
            package = copy
        } catch {
            copy.remove()
            throw error
        }
    }

    /// `realpath(3)` of `url`, or its path when that fails.
    static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else {
            return url.path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The bytes of recording `name` with the copy's paths put back.
    func recorded(_ name: String) throws -> Data {
        Data(try IndexFixture.text(name, restoring: paths).utf8)
    }

    /// The recorded first build's output, read: `build.stderr` with
    /// `build.stdout` as its task log.
    func output() throws -> BuildOutput {
        BuildOutputReader.read(stderr: try recorded("build.stderr"), log: try recorded("build.stdout"))
    }

    /// A timing mapper onto the copy, the files `changedFiles` changed.
    func mapper(changedFiles: Set<String>) -> TimingMapper {
        TimingMapper(measured: measured, root: root, build: build, changedFiles: changedFiles)
    }

    /// A warning reader for the copy, the files `changedFiles` changed.
    func warningReader(changedFiles: Set<String>) -> WarningReader {
        WarningReader(measured: measured, targets: targets, root: root, build: build, changedFiles: changedFiles)
    }

    /// The key of the record of the copy's `file` (relative to `Sources/`
    /// or `Tests/` as given) whose key ends with `suffix`.
    func key(_ suffix: String, in file: String) -> String? {
        measured.records.first { $0.file == file && $0.key.hasSuffix(suffix) }?.key
    }

    /// Removes the copy.
    func remove() {
        package.remove()
    }
}
