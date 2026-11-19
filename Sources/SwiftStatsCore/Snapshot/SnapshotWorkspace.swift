//
//  SnapshotWorkspace.swift
//  SwiftStatsCore
//
//  A package with its store (PRD §10): what `scan`, `report` and `diff`
//  share. It picks snapshots for `report` and `diff`, and scans a revision
//  that has none from an export into the invoking package's store, using the
//  revision's own `.swiftstats.yml` unless a configuration file was given.
//  A stored dirty snapshot stands for the working tree only while its hash
//  of the changes matches the tree's.
//

import Foundation

/// A package, its configuration and its snapshot store.
public struct SnapshotWorkspace {
    /// The package root.
    public let root: URL
    /// The store.
    public let store: SnapshotStore
    /// The package's configuration, or the one given on the command line.
    public let configuration: SwiftStatsConfiguration
    /// The configuration file given on the command line, if any.
    let configurationFile: URL?
    /// Scans with snapshot metadata.
    let scanner: SnapshotScanner
    /// Learns the package's name.
    let describer: any PackageDescriber
    /// The store's path from the package root when it is kept inside the
    /// package outside `.swiftstats/`, so its writes don't dirty the tree.
    let storeInPackage: [String]

    /// The workspace of the package at `root`, with its store at `storeOverride`,
    /// else where its configuration says, else the default.
    public init(
        packageRoot root: URL,
        configurationFile: URL?,
        storeOverride: String?,
        build: SwiftStatsBuild,
        describer: any PackageDescriber,
        tools: ToolLocator
    ) throws {
        let packageRoot = root.standardizedFileURL
        guard FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("Package.swift").path) else {
            throw ScanError.notAPackage(packageRoot.path)
        }
        let loaded = try StoreLocation.configuration(packageRoot: packageRoot, file: configurationFile)
        let url = StoreLocation.resolve(packageRoot: packageRoot, configuration: loaded, override: storeOverride)
        try StoreLocation.prepare(url, packageRoot: packageRoot)
        self.root = packageRoot
        self.configuration = loaded
        self.configurationFile = configurationFile
        self.describer = describer
        // After the store exists, so its directory's symlinks resolve.
        store = try SnapshotStore(at: url)
        storeInPackage = StoreLocation.pathInPackage(url, packageRoot: packageRoot).map { [$0] } ?? []
        scanner = SnapshotScanner(scanner: PackageScanner(describer: describer, tools: tools), build: build)
    }

    /// The commit `revision` names, or an error saying it names none.
    private static func commit(of revision: String, in root: URL) throws -> String {
        guard let commit = RevisionExport.commit(of: revision, in: root) else {
            throw StoreError.noSnapshot("\(revision), which names no commit")
        }
        return commit
    }

    /// The signals of snapshot `id`, with this workspace's thresholds.
    public func signals(id: Int64) throws -> [SignalResult] {
        SignalEngine.signals(of: try store.load(id: id), thresholds: configuration.signals)
    }

    /// Scans the working tree, reading history from `history`, stores the
    /// snapshot and returns it with its id.
    public func scanWorkingTree(history: HistorySource = .automatic) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        let snapshot = try scanner.scan(
            packageAt: root,
            configurationFile: configurationFile ?? StoreLocation.localConfiguration(packageRoot: root),
            ignoring: storeInPackage,
            history: history
        )
        return (snapshot, try store.save(snapshot))
    }

    /// The snapshot `report` shows: `revision`'s clean one when given; else
    /// the working tree's: HEAD's clean snapshot when the tree is clean, its
    /// dirty snapshot when that covers the tree's current changes, and an
    /// error when the tree has changes no snapshot covers; outside git, the latest.
    public func reportSnapshotID(revision: String?) throws -> Int64 {
        let name = try describer.describePackage(at: root).name
        let git = GitReader.read(packageRoot: root, ignoring: storeInPackage)
        if let revision {
            guard let commit = RevisionExport.commit(of: revision, in: root) else {
                throw StoreError.noSnapshot("\(revision), which names no commit")
            }
            return try require(name, git, commit: commit, shown: revision)
        }
        guard let commit = git.commit else {
            guard let latest = try store.latestSnapshotID(package: name, packagePath: git.packagePath) else {
                throw StoreError.noSnapshot(name)
            }
            return latest
        }
        guard git.isDirty else {
            return try require(name, git, commit: commit, shown: "HEAD")
        }
        guard let current = try currentDirtySnapshot(name, git, commit: commit) else {
            throw StoreError.workingTreeChanged(name)
        }
        return current
    }

    /// The ids of the snapshots `diff` compares: `older`'s and `newer`'s
    /// (HEAD when nil) clean snapshots, scanning any that is missing, or
    /// both when `rescan` is set. With `includeDirty`, a nil `newer` on a
    /// dirty tree means the working tree itself.
    public func diffSnapshotIDs(
        older: String,
        newer: String?,
        includeDirty: Bool,
        rescan: Bool
    ) throws -> (older: Int64, newer: Int64) {
        let name = try describer.describePackage(at: root).name
        let git = GitReader.read(packageRoot: root, ignoring: storeInPackage)
        let olderCommit = try Self.commit(of: older, in: root)
        let olderID = try cleanSnapshotID(olderCommit, name: name, git: git, rescan: rescan)
        if newer == nil, includeDirty, git.isDirty, let commit = git.commit {
            if rescan == false, let current = try currentDirtySnapshot(name, git, commit: commit) {
                return (olderID, current)
            }
            return (olderID, try scanWorkingTree().id)
        }
        let newerCommit = try Self.commit(of: newer ?? "HEAD", in: root)
        guard newerCommit != olderCommit else {
            // Rescanning the same commit again would replace the first scan.
            return (olderID, olderID)
        }
        return (olderID, try cleanSnapshotID(newerCommit, name: name, git: git, rescan: rescan))
    }

    /// `commit`'s clean snapshot, scanned first when missing or when
    /// `rescan` is set: in place when it is HEAD and the tree is clean,
    /// otherwise from an export.
    private func cleanSnapshotID(_ commit: String, name: String, git: GitState, rescan: Bool) throws -> Int64 {
        if rescan == false, let existing = try snapshot(name, git, commit: commit, isDirty: false) {
            return existing
        }
        if commit == git.commit, git.isDirty == false {
            return try scanWorkingTree().id
        }
        let exported = try RevisionExport.export(commit: commit, packagePath: git.packagePath, from: root)
        defer { try? FileManager.default.removeItem(at: RevisionExport.workDirectory(of: exported)) }
        let state = GitState(commit: commit, branch: nil, isDirty: false, dirtyHash: nil, packagePath: git.packagePath)
        let snapshot = try scanner.scan(
            packageAt: exported,
            configurationFile: configurationFile ?? StoreLocation.localConfiguration(packageRoot: exported),
            git: state,
            history: .skipped("exported revision")
        )
        return try store.save(snapshot)
    }

    /// HEAD's stored dirty snapshot when its hash of the changes is the
    /// working tree's; nil when there is none or the tree has moved on.
    private func currentDirtySnapshot(_ name: String, _ git: GitState, commit: String) throws -> Int64? {
        guard let id = try snapshot(name, git, commit: commit, isDirty: true),
              try store.info(id: id).git.dirtyHash == git.dirtyHash else {
            return nil
        }
        return id
    }

    /// The clean snapshot at `commit`, or an error naming `shown`.
    private func require(_ name: String, _ git: GitState, commit: String, shown: String) throws -> Int64 {
        guard let id = try snapshot(name, git, commit: commit, isDirty: false) else {
            throw StoreError.noSnapshot("\(name) at \(shown)")
        }
        return id
    }

    /// The stored snapshot of package `name`, where `git` places it, at
    /// `commit` with the given dirtiness.
    private func snapshot(_ name: String, _ git: GitState, commit: String, isDirty: Bool) throws -> Int64? {
        try store.snapshotID(package: name, packagePath: git.packagePath, commit: commit, isDirty: isDirty)
    }
}
