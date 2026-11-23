//
//  StoreLocation.swift
//  SwiftStatsCore
//
//  Where a package's snapshot store is (PRD D9): `--store`, else `store:` in
//  `.swiftstats.yml`, else `.swiftstats/stats.sqlite` in the package. The
//  `.swiftstats` directory, which also holds the coverage build, ignores
//  itself with a `.gitignore` of `*`, so SwiftStats never edits the
//  package's own `.gitignore`.
//

import Foundation

/// Finds and prepares a package's store.
public enum StoreLocation {
    /// The default store directory, in the package root.
    public static let directoryName = ".swiftstats"
    /// The default store file name.
    public static let fileName = "stats.sqlite"

    /// The store for the package at `root`: `override` (relative to the
    /// current directory) when given, else the configuration's `store`
    /// (relative to the package root), else the default.
    public static func resolve(
        packageRoot root: URL,
        configuration: SwiftStatsConfiguration,
        override: String?
    ) -> URL {
        if let override {
            return URL(fileURLWithPath: override).standardized
        }
        if let store = configuration.store {
            return URL(fileURLWithPath: store, relativeTo: root.standardizedFileURL).standardizedFileURL
        }
        return defaultURL(packageRoot: root)
    }

    /// `.swiftstats/stats.sqlite` in the package at `root`.
    public static func defaultURL(packageRoot root: URL) -> URL {
        root.standardizedFileURL.appendingPathComponent(directoryName).appendingPathComponent(fileName)
    }

    /// SwiftMutator's log in the package at `root`
    /// (`.swiftstats/mutation/swift-mutator.log`, M6) when a mutation step
    /// wrote it at or after `start` (from the start of its second, for
    /// file systems that keep whole seconds); nil when none did, as when
    /// the collector was disabled, its tools weren't found or the run was
    /// refused, so a log an earlier scan left isn't named as this one's.
    public static func mutationLog(packageRoot root: URL, writtenSince start: Date) -> URL? {
        let log = MutationDirectory.log(packageRoot: root)
        let values = try? log.resourceValues(forKeys: [.contentModificationDateKey])
        let second = Date(timeIntervalSince1970: start.timeIntervalSince1970.rounded(.down))
        guard let modified = values?.contentModificationDate, modified >= second else {
            return nil
        }
        return log
    }

    /// Creates the default store directory's `.gitignore` when `store` is in
    /// it and the file is missing.
    public static func prepare(_ store: URL, packageRoot root: URL) throws {
        let directory = root.standardizedFileURL.appendingPathComponent(directoryName)
        guard store.deletingLastPathComponent().standardizedFileURL.path == directory.path else {
            return
        }
        try ignoreDirectory(packageRoot: root)
    }

    /// Creates `.swiftstats/` in the package at `root`, and its `.gitignore`
    /// of `*` when that file is missing, and returns the directory. The
    /// coverage build lives there whether or not the store does (an outside
    /// `store:`, or `--no-store`), so it never shows as untracked.
    @discardableResult
    public static func ignoreDirectory(packageRoot root: URL) throws -> URL {
        let directory = root.standardizedFileURL.appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ignore = directory.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: ignore.path) == false {
            try "*\n".write(to: ignore, atomically: true, encoding: .utf8)
        }
        return directory
    }

    /// `store`'s path from the package root when it lies inside the package
    /// but outside `.swiftstats/` (which ignores itself); otherwise nil.
    public static func pathInPackage(_ store: URL, packageRoot root: URL) -> String? {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let directory = store.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let storePath = directory.appendingPathComponent(store.lastPathComponent).path
        guard storePath.hasPrefix(rootPath) else {
            return nil
        }
        let relative = String(storePath.dropFirst(rootPath.count))
        return relative.hasPrefix(directoryName + "/") ? nil : relative
    }

    /// The package's own `.swiftstats.yml`, when present.
    public static func localConfiguration(packageRoot root: URL) -> URL? {
        let local = root.standardizedFileURL.appendingPathComponent(SwiftStatsConfiguration.fileName)
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    /// The configuration for the package at `root`: `file` when given, else
    /// its `.swiftstats.yml` when present, else the default.
    public static func configuration(packageRoot root: URL, file: URL?) throws -> SwiftStatsConfiguration {
        try SwiftStatsConfiguration.load(file ?? localConfiguration(packageRoot: root), root: root.standardizedFileURL)
    }
}
