//
//  BuildHarness.swift
//  SwiftStatsCoreTests
//
//  Runs the `build` collector (M7, design §1.3) with a `FakeToolchain`
//  acting out a build scenario on a fresh package holding a few of the
//  Index fixture's file names, for the T1 build's tests. The package's
//  files are passed as the scan's file records, hashed as they are before
//  the run. Nothing is built.
//

import Foundation
@testable import SwiftStatsCore

/// Runs the `build` collector against fake toolchains.
enum BuildHarness {
    /// What a run left: its result, and the toolchain and package it ran
    /// with, for their logs and files.
    struct Outcome {
        /// The run.
        let run: BuildRun
        /// The fake toolchain.
        let toolchain: FakeToolchain
        /// The package root, as the run was given it.
        let root: URL
        /// The package root, as its real path.
        let realRoot: URL

        /// The run's build directory, as its real path.
        var build: URL {
            realRoot.appendingPathComponent(".swiftstats/index-build")
        }

        /// The calls of the toolchain's own `swift`, each its arguments
        /// joined by tabs.
        var swiftCalls: [String] {
            toolchain.calls(of: "swift")
        }

        /// Whether the toolchain's `swift` was asked to build.
        var built: Bool {
            swiftCalls.contains { $0.hasPrefix("build\t") }
        }
    }

    /// The package's source files, by path relative to the root.
    static let files = [
        "Sources/IndexCore/Formatting.swift": "public func formatLine() -> String { \"line\" }\n",
        "Sources/IndexCore/Ring.swift": "public struct Ring {}\n",
        "Sources/IndexCore/Types.swift": "public struct Alpha {}\n",
        "Sources/IndexCore/Unused.swift": "struct Unused {}\n",
        "Sources/IndexCore/Warnings.swift": "func warned() {}\n",
        "Sources/Kits/Kit.swift": "public func kit() {}\n",
        "Sources/Kits/Relay.swift": "public func relay() {}\n"
    ]

    /// The file records a scan of the package at `root` would give its
    /// files, hashed as they are now.
    static func records(of root: URL) -> [FileRecord] {
        files.keys.sorted().map { path in
            FileRecord(
                path: path,
                module: path.hasPrefix("Sources/Kits/") ? "index-kit" : "IndexCore",
                lines: 1,
                strippedLines: 1,
                generated: false,
                sha256: ContentHash.sha256(ofFileAt: root.appendingPathComponent(path)) ?? ""
            )
        }
    }

    /// Runs the collector with a fake toolchain acting out `scenario` on
    /// the package, given through a symbolic link to its folder when
    /// `linked`, after `prepare` has run on its real root, and passes what
    /// it left to `check`.
    static func run(
        _ scenario: FakeToolchain.BuildScenario,
        linked: Bool,
        prepare: (URL) throws -> Void,
        check: (Outcome) throws -> Void
    ) throws {
        let toolchain = try FakeToolchain.make(build: scenario)
        defer { toolchain.remove() }
        let package = try TemporaryPackage(files)
        defer { package.remove() }
        let realRoot = URL(fileURLWithPath: WorkCopyHarness.realPath(package.root))
        try prepare(realRoot)
        let link = package.root.deletingLastPathComponent().appendingPathComponent("BuildLink-\(UUID().uuidString)")
        if linked {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: package.root)
        }
        defer { try? FileManager.default.removeItem(at: link) }
        let root = linked ? link : package.root
        let run = BuildAdapter.run(swift: toolchain.proxy, root: root, files: records(of: realRoot)) { $0 }
        try check(Outcome(run: run, toolchain: toolchain, root: root, realRoot: realRoot))
    }

    /// Runs the collector as `run(_:linked:prepare:check:)` does, on the
    /// package's own folder with nothing prepared.
    static func run(_ scenario: FakeToolchain.BuildScenario, check: (Outcome) throws -> Void) throws {
        try run(scenario, linked: false, prepare: { _ in /* Nothing to prepare. */ }, check: check)
    }

    /// Runs the collector as `run(_:linked:prepare:check:)` does, on the
    /// package's own folder after `prepare`.
    static func run(
        _ scenario: FakeToolchain.BuildScenario,
        prepare: (URL) throws -> Void,
        check: (Outcome) throws -> Void
    ) throws {
        try run(scenario, linked: false, prepare: prepare, check: check)
    }

    /// The text of the Index fixture's recording `name` as the fake
    /// toolchain at `toolchain` restores it for the package at `root`
    /// (real path) built in `build`.
    static func restored(_ name: String, toolchain: FakeToolchain, root: URL, build: URL) throws -> String {
        let top = toolchain.directory.path
        let replacements = [
            ("@ROOT@", root.path),
            ("@BUILD@", build.path),
            ("@PARENT@", root.deletingLastPathComponent().path),
            ("@DEP@", "\(top)/IndexDep"),
            ("@TOOLCHAIN@", top),
            ("@DEVELOPER@", "\(top)/Developer"),
            ("@TMP@", "\(top)/tmp")
        ]
        return replacements.reduce(try IndexFixture.text(name)) { text, replacement in
            text.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
    }
}
