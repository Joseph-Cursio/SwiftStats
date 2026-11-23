//
//  SnapshotWorkspace.swift
//  SwiftStatsCore
//
//  A package with its store (PRD §10): what `scan`, `report` and `diff`
//  share. It picks snapshots for `report` and `diff`, and scans a revision
//  that has none from an export into the invoking package's store, using the
//  revision's own `.swiftstats.yml` unless a configuration file was given.
//  A stored dirty snapshot stands for the working tree only while its hash
//  of the changes matches the tree's. Before `scan --mutation --since`, or
//  the resume of such a run, it chooses the stored snapshot the run merges
//  with (M6, `MutationBase`).
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

    /// The signals of snapshot `id`, with this workspace's thresholds, and
    /// for divergent clones the earlier snapshot it chooses.
    public func signals(id: Int64) throws -> [SignalResult] {
        SignalEngine.signals(of: try signalInputs(for: try store.load(id: id)), thresholds: configuration.signals)
    }

    /// Scans the working tree, reading history from `history` and running
    /// the coverage and SwiftMutator collectors when `tiers` asks for them,
    /// stores the snapshot as `save(_:drop:)` does and returns what it
    /// stored with its id. Before anything runs, `--since` chooses the
    /// stored snapshot it merges with and is refused when there is none it
    /// can merge with (`StoreError.noMutationBase`, `MutationBase`), and
    /// `--resume` is refused (`ScanError.mutationRefused`) when no run is
    /// pending, or when the tree, the settings, the copy or the results
    /// file don't let it go on (`MutationResume`); the resume of a
    /// `--since` run chooses its base again. Neither is checked when the
    /// collector's tools aren't found, which skips it. A scan asking for
    /// coverage or SwiftMutator is refused, before the run, as its save
    /// would refuse held results it can't keep, and a SwiftMutator run
    /// that ran is kept until its snapshot is stored
    /// (`SnapshotWorkspace+Held`).
    public func scanWorkingTree(
        history: HistorySource = .automatic,
        tiers: RequestedTiers = .syntaxOnly,
        drop: DropOptions = []
    ) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        let git = GitReader.read(packageRoot: root, ignoring: storeInPackage)
        let base = try mutationBase(tiers.mutation, git: git)
        let saving = try heldResultsChecks(git: git, tiers: tiers, drop: drop)
        let snapshot = try scanner.saving(saving).scan(
            packageAt: root,
            configurationFile: configurationFile ?? StoreLocation.localConfiguration(packageRoot: root),
            git: git,
            ignoring: storeInPackage,
            history: history,
            tiers: tiers.merging(with: base)
        )
        return try storing(snapshot, drop: drop)
    }

    /// The stored snapshot the SwiftMutator run `request` asks for merges
    /// with: for `--since`, the one its revision names, checked against the
    /// tools and settings; for the resume of a `--since` run, the one the
    /// pending run recorded, chosen again. Nil for a full run, the resume
    /// of one, and when the tools aren't found. It throws the refusal that
    /// stops the scan before anything runs. `git` is the package's state.
    private func mutationBase(_ request: MutationRequest?, git: GitState) throws -> MutationBase? {
        guard let request else {
            return nil
        }
        if case .resume = request, let reason = MutationResume.refusal(
            root: root,
            configuration: configuration,
            locator: scanner.scanner.tools,
            ignoring: storeInPackage
        ) {
            throw ScanError.mutationRefused(reason)
        }
        guard case let .found(mutator, swift) = MutationTools.resolve(
            root: root,
            configuration: configuration,
            locator: scanner.scanner.tools
        ) else {
            return nil
        }
        let lookup = MutationBase.Lookup(
            store: store,
            package: try describer.describePackage(at: root).name,
            root: root,
            git: git
        )
        switch request {
        case .full:
            return nil

        case .resume:
            let pending = try? PendingMutationRun.read(in: MutationDirectory(lookingIn: root))
            return try pending?.base.map { recorded in try MutationBase.resumed(recorded, lookup: lookup) }

        case .since(let revision):
            let base = try MutationBase.select(revision: revision, lookup: lookup)
            if let reason = base.settingsRefusal(
                mutator: mutator,
                settings: configuration.collectors[MutationAdapter.name],
                toolchain: MutationBase.toolchainLine(swift: swift, root: root),
                root: root,
                environment: MutationBase.sdkEnvironment(of: ProcessInfo.processInfo.environment)
            ) ?? base.manifestRefusal(root: root) {
                throw StoreError.noMutationBase(reason)
            }
            return base
        }
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
    /// dirty tree means the working tree itself. Each scan is stored as
    /// `save(_:drop:)` does.
    public func diffSnapshotIDs(
        older: String,
        newer: String?,
        includeDirty: Bool,
        rescan: Bool,
        drop: DropOptions = []
    ) throws -> (older: Int64, newer: Int64) {
        let name = try describer.describePackage(at: root).name
        let git = GitReader.read(packageRoot: root, ignoring: storeInPackage)
        let olderCommit = try Self.commit(of: older, in: root)
        let olderID = try cleanSnapshotID(
            olderCommit,
            name: name,
            git: git,
            rescan: rescan,
            drop: drop
        )
        if newer == nil, includeDirty, git.isDirty, let commit = git.commit {
            if rescan == false, let current = try currentDirtySnapshot(name, git, commit: commit) {
                return (olderID, current)
            }
            return (olderID, try scanWorkingTree(drop: drop).id)
        }
        let newerCommit = try Self.commit(of: newer ?? "HEAD", in: root)
        guard newerCommit != olderCommit else {
            // Rescanning the same commit again would replace the first scan.
            return (olderID, olderID)
        }
        return (
            olderID,
            try cleanSnapshotID(newerCommit, name: name, git: git, rescan: rescan, drop: drop)
        )
    }

    /// `commit`'s clean snapshot, scanned first when missing or when
    /// `rescan` is set: in place when it is HEAD and the tree is clean,
    /// otherwise from an export; stored as `save(_:drop:)` does.
    private func cleanSnapshotID(
        _ commit: String,
        name: String,
        git: GitState,
        rescan: Bool,
        drop: DropOptions
    ) throws -> Int64 {
        if rescan == false, let existing = try snapshot(name, git, commit: commit, isDirty: false) {
            return existing
        }
        if commit == git.commit, git.isDirty == false {
            return try scanWorkingTree(drop: drop).id
        }
        let scanned = try scanExport(commit, git: git, scanner: scanner, history: .skipped("exported revision"))
        return try save(scanned.snapshot, drop: drop).id
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
