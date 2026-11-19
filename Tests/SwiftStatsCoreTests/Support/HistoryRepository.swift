import Foundation
@testable import SwiftStatsCore

/// A package in a fresh git repository whose commits have fixed dates, so
/// history, its window and its signals are the same on every run.
struct HistoryRepository {
    /// Describes a package from its directories, as they are when asked:
    /// each `Sources/<X>` is a library and each `Tests/<X>` a test target,
    /// but `Tests/Fixtures`, which a manifest would leave out. The package is
    /// named by a `name: "<X>"` in `Package.swift`, or `Probe`.
    struct DiskDescriber: PackageDescriber {
        /// A target directory no target compiles.
        static let fixtures = "Fixtures"

        /// The `name: "<X>"` in the package's manifest, or `Probe`.
        private static func name(of packageRoot: URL) -> String {
            let manifestURL = packageRoot.appendingPathComponent("Package.swift")
            let manifest = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
            guard let range = manifest.range(of: #"name: "[^"]+""#, options: .regularExpression) else {
                return "Probe"
            }
            return String(manifest[range].dropFirst("name: \"".count).dropLast())
        }

        func describePackage(at packageRoot: URL) -> DescribedPackage {
            var targets: [DescribedTarget] = []
            for (folder, type) in [("Sources", "library"), ("Tests", "test")] {
                let base = packageRoot.appendingPathComponent(folder)
                let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
                for name in names.sorted() where name != Self.fixtures {
                    let directory = base.appendingPathComponent(name)
                    let files = FileManager.default.enumerator(atPath: directory.path)?
                        .compactMap { $0 as? String }
                        .filter { $0.hasSuffix(".swift") }
                        .sorted() ?? []
                    if files.isEmpty == false {
                        targets.append(DescribedTarget(
                            name: name,
                            type: type,
                            moduleType: "SwiftTarget",
                            path: "\(folder)/\(name)",
                            sources: files
                        ))
                    }
                }
            }
            return DescribedPackage(name: Self.name(of: packageRoot), targets: targets)
        }
    }

    /// Seconds from 1970 to 2026-01-01T00:00:00Z, day 0 of every repository.
    static let dayZero = 1_767_225_600

    /// The repository and package root.
    let root: URL

    /// A new repository holding an empty `Package.swift`.
    init() throws {
        root = try SnapshotHarness.temporaryDirectory("HistoryRepository")
        try write(["Package.swift": "// swift-tools-version: 6.0\n"])
        try git(["init", "-q", "-b", "main"])
    }

    /// The environment dating a git command `day` days after day zero.
    static func dated(_ day: Int) -> [String: String] {
        let date = "@\(dayZero + day * HistoryCollector.day) +0000"
        return ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date]
    }

    /// Writes `files` (paths relative to the root).
    func write(_ files: [String: String]) throws {
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Moves the file at `from` to `destination` with git.
    func move(_ from: String, to destination: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(destination).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try git(["mv", from, destination])
    }

    /// Commits everything with `message`, dated `day` days after day zero.
    @discardableResult
    func commit(_ message: String, day: Int) throws -> String {
        try commit(message, day: day, options: [])
    }

    /// Commits everything with `message`, dated `day` days after day zero,
    /// passing `options` to `git commit` too.
    @discardableResult
    func commit(_ message: String, day: Int, options: [String]) throws -> String {
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", message] + options, environment: Self.dated(day))
        return try git(["rev-parse", "HEAD"])
    }

    /// Runs git in the repository with a fixed identity.
    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        try git(arguments, environment: [:])
    }

    /// Runs git in the repository with a fixed identity and extra environment.
    @discardableResult
    func git(_ arguments: [String], environment: [String: String]) throws -> String {
        let identity = [
            "-c", "user.name=SwiftStats Tests", "-c", "user.email=tests@example.invalid", "-c", "commit.gpgsign=false"
        ]
        let data = try ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: identity + arguments,
            in: root,
            environment: environment
        )
        let output = String(bytes: data, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A snapshot scanner for this repository, as the test build.
    func scanner() -> SnapshotScanner {
        scanner(build: SnapshotHarness.build)
    }

    /// A snapshot scanner for this repository, as `build`.
    func scanner(build: SwiftStatsBuild) -> SnapshotScanner {
        let packageScanner = PackageScanner(describer: DiskDescriber(), tools: SnapshotHarness.noTools)
        return SnapshotScanner(scanner: packageScanner, build: build)
    }

    /// The working tree scanned with history read from HEAD, as the test build.
    func scan() throws -> ScannedSnapshot {
        try scan(build: SnapshotHarness.build)
    }

    /// The working tree scanned with history read from HEAD, as `build`.
    func scan(build: SwiftStatsBuild) throws -> ScannedSnapshot {
        try scanner(build: build).scan(
            packageAt: root,
            configurationFile: StoreLocation.localConfiguration(packageRoot: root),
            toolchain: SnapshotHarness.toolchain,
            date: SnapshotHarness.date
        )
    }

    /// The history of a scan of the working tree.
    func history() throws -> HistoryReport {
        let report = try scan().report
        guard let history = report.history else {
            let status = report.collectors.first { $0.name == HistoryCollector.name }
            throw ScanError.commandFailed("history", -1, status?.reason ?? "no history")
        }
        return history
    }

    /// A workspace on this repository with its store in the repository's
    /// `.swiftstats/`, scanning as the test build.
    func workspace() throws -> SnapshotWorkspace {
        try workspace(build: SnapshotHarness.build)
    }

    /// A workspace on this repository with its store in the repository's
    /// `.swiftstats/`, scanning as `build`.
    func workspace(build: SwiftStatsBuild) throws -> SnapshotWorkspace {
        try SnapshotWorkspace(
            packageRoot: root,
            configurationFile: nil,
            storeOverride: nil,
            build: build,
            describer: DiskDescriber(),
            tools: SnapshotHarness.noTools
        )
    }

    /// Removes the repository.
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension HistoryReport {
    /// The history of the family whose id contains `name`.
    func family(_ name: String) -> FamilyHistory? {
        families.first { $0.family.contains(name) }
    }
}
