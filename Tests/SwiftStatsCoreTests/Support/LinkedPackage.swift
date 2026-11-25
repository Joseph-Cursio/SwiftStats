//
//  LinkedPackage.swift
//  SwiftStatsCoreTests
//
//  A package written to a temporary directory with some of its sources
//  reached through symbolic links, measured as a scan measures it, for the
//  tests of sources whose real paths differ from the package's spelling
//  (M7, `SourcePaths`).
//

import Foundation
@testable import SwiftStatsCore

/// A package written to a temporary directory, measured as a scan
/// measures it, its sources spelled as `targets` gives them.
struct LinkedPackage {
    /// The package.
    let package: TemporaryPackage
    /// Another temporary directory, outside the package, that a source
    /// may be linked into.
    let outside: URL
    /// Its measurements.
    let measured: ScanMeasurements
    /// Its targets.
    let targets: [TargetSummary]
    /// The root's real path.
    let root: String

    /// The scratch folder's real path.
    var build: String {
        root + "/.swiftstats/index-build"
    }

    /// The package's description.
    var described: DescribedPackage {
        DescribedPackage(name: "Probe", targets: package.targets)
    }

    /// The package holding `files`, with `links` (a path in the package
    /// to the link's destination, relative to the link's folder or,
    /// starting `@OUTSIDE@/`, in `outside`) made after the files are
    /// written, measured as `targets` describes it.
    init(files: [String: String], links: [String: String], targets: [DescribedTarget]) throws {
        try self.init(files: files, links: links, targets: targets, excluded: [])
    }

    /// The package holding `files`, with `links` made after the files are
    /// written (as `init(files:links:targets:)` makes them), measured as
    /// `targets` describes it, less the files `excluded`
    /// (`.swiftstats.yml` globs) leaves out.
    init(
        files: [String: String],
        links: [String: String],
        targets: [DescribedTarget],
        excluded: [String]
    ) throws {
        let manager = FileManager.default
        package = try TemporaryPackage(files, targets: targets)
        outside = manager.temporaryDirectory.appendingPathComponent("LinkedSourceTests-\(UUID().uuidString)")
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("func distant() -> Int {\n    3\n}\n".utf8).write(to: outside.appendingPathComponent("Far.swift"))
        for (link, destination) in links {
            let url = package.root.appendingPathComponent(link)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let marker = "@OUTSIDE@/"
            let target = destination.hasPrefix(marker)
                ? outside.appendingPathComponent(String(destination.dropFirst(marker.count))).path
                : destination
            try manager.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        }
        let configuration = SwiftStatsConfiguration(
            excluded: excluded,
            generated: GeneratedCode.defaultGlobs,
            collectors: [:],
            store: nil,
            history: .standard,
            signals: SignalThresholds(),
            unusedKeys: [],
            source: nil
        )
        let resolved = TargetResolver.resolve(DescribedPackage(name: "Probe", targets: targets))
        self.targets = PackageScanner.excluding(resolved, by: configuration).targets
        measured = PackageScanner.measure(self.targets, root: package.root, configuration: configuration)
        root = WorkCopyHarness.realPath(package.root)
    }

    /// The real path of the file at `path` in the package.
    func real(_ path: String) -> String {
        WorkCopyHarness.realPath(package.root.appendingPathComponent(path))
    }

    /// A unit of `module` whose main file is `path`'s real path,
    /// naming one record, `record`.
    func unit(_ name: String, module: String, path: String, record: String) -> IndexUnitFact {
        IndexUnitFact(
            name: name,
            module: module,
            mainFile: real(path),
            target: "arm64-apple-macos14.0",
            isSystem: false,
            modified: IndexUnitFact.ModificationDate(seconds: 1, nanoseconds: 0),
            records: [record],
            moduleDependencies: []
        )
    }

    /// A function timing entry at `path`'s real path.
    func timing(_ path: String, line: Int, column: Int) -> TimingEntry {
        TimingEntry(
            kind: .function,
            hundredths: 100,
            place: BuildPlace(path: real(path), line: line, column: column),
            declaration: nil
        )
    }

    /// A warning at `path`'s real path.
    func warning(_ path: String, line: Int, column: Int) -> BuildDiagnostic {
        BuildDiagnostic(
            severity: .warning,
            location: .file(BuildPlace(path: real(path), line: line, column: column)),
            message: "a warning",
            identifier: "probe_warning",
            group: nil,
            origin: nil
        )
    }

    /// An outskirts context for the package.
    func peripheryContext() throws -> PeripheryOutput.Context {
        PeripheryOutput.Context(
            root: root,
            scratch: build,
            package: described,
            modules: try BuildSession.moduleMap(of: described),
            files: Dictionary(measured.files.map { ($0.path, $0.module) }) { first, _ in first },
            changedFiles: [],
            records: measured.records,
            localUSRs: []
        )
    }

    /// Removes the package and the outside directory.
    func remove() {
        package.remove()
        try? FileManager.default.removeItem(at: outside)
    }
}
