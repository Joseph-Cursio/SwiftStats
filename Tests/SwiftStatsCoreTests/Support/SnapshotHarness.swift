import Foundation
@testable import SwiftStatsCore

/// Snapshots of temporary packages, with a fixed build, toolchain and date
/// so tests compare what they mean to.
enum SnapshotHarness {
    /// The build tests scan as unless they say otherwise.
    static let build = SwiftStatsBuild(identity: "inputs:test", label: nil)
    /// A toolchain that needs no commands.
    static let toolchain = Toolchain(swiftVersion: "test swift", swiftlySelection: nil, sdkVersion: nil)
    /// Seconds from 1970 to 2027-01-15T08:00:00Z.
    private static let fixedSeconds: TimeInterval = 1_800_000_000
    /// A fixed scan date: 2027-01-15T08:00:00Z.
    static let date = Date(timeIntervalSince1970: fixedSeconds)
    /// Finds no external tools, so every external collector is skipped.
    static let noTools = ToolLocator { _ in nil }

    /// A new, empty temporary directory.
    static func temporaryDirectory(_ prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The git state of a clean package at `commit`.
    static func git(commit: String?) -> GitState {
        GitState(commit: commit, branch: nil, isDirty: false, dirtyHash: nil, packagePath: "")
    }

    /// `package` scanned at `commit` as the test build, with no tools.
    static func scan(_ package: TemporaryPackage, commit: String?) throws -> ScannedSnapshot {
        try scan(package, commit: commit, build: build, tools: noTools)
    }

    /// `package` scanned as `build`, at `commit`, finding tools with `tools`.
    static func scan(
        _ package: TemporaryPackage,
        commit: String?,
        build: SwiftStatsBuild,
        tools: ToolLocator
    ) throws -> ScannedSnapshot {
        try SnapshotScanner(scanner: PackageScanner(describer: package.describer, tools: tools), build: build)
            .scan(
                packageAt: package.root,
                configurationFile: StoreLocation.localConfiguration(packageRoot: package.root),
                git: git(commit: commit),
                toolchain: toolchain,
                date: date
            )
    }

    /// `files` as a package, scanned with no tools as the test build at
    /// `commit`, stored in `store` and read back.
    static func stored(_ files: [String: String], commit: String, in store: SnapshotStore) throws -> StoredSnapshot {
        let package = try TemporaryPackage(files)
        defer { package.remove() }
        let snapshot = try scan(package, commit: commit, build: build, tools: noTools)
        return try store.load(id: try store.save(snapshot))
    }

    /// Runs git with a fixed identity in `directory`, returning its output.
    @discardableResult
    static func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let identity = [
            "-c", "user.name=SwiftStats Tests", "-c", "user.email=tests@example.invalid", "-c", "commit.gpgsign=false"
        ]
        let data = try ProcessRunner.run(executable: "/usr/bin/git", arguments: identity + arguments, in: directory)
        return String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Runs `sqlite3` on the database at `url`.
    static func sqlite(_ url: URL, _ statement: String) throws {
        _ = try ProcessRunner.run(
            executable: "/usr/bin/sqlite3",
            arguments: [url.path, statement],
            in: url.deletingLastPathComponent()
        )
    }
}
