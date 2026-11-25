//
//  SnapshotScanner.swift
//  SwiftStatsCore
//
//  A scan with its snapshot metadata (PRD §6.2). Git state is read before
//  any collector runs, since SwiftPM's own commands write untracked files
//  into `.build`.
//

import Foundation

/// Scans a package and describes the snapshot.
public struct SnapshotScanner {
    /// Formats snapshot dates: ISO 8601, UTC, whole seconds.
    private static let dateFormat = Date.ISO8601FormatStyle(timeZone: .gmt)

    /// The collectors whose build identity is their toolchain's `swift`
    /// version line, which their run reports.
    private static let toolchainIdentified: Set = [CoverageAdapter.name, BuildAdapter.name]
    /// The collectors linked into SwiftStats rather than run, each named
    /// by the revision it is pinned to.
    private static let linkedIdentities = [
        EffectCollector.name: EffectInferenceRevision.identity,
        IndexAdapter.name: IndexStoreReader.identity
    ]

    /// The scan itself.
    let scanner: PackageScanner
    /// Which build of SwiftStats is scanning.
    let build: SwiftStatsBuild

    /// A snapshot scanner that scans with `scanner` as build `build`.
    public init(scanner: PackageScanner, build: SwiftStatsBuild) {
        self.scanner = scanner
        self.build = build
    }

    /// `date` as a snapshot records it.
    public static func format(_ date: Date) -> String {
        dateFormat.format(date)
    }

    /// The snapshot's record of a collector's run other than SwiftStats' own
    /// and the history's.
    static func info(for status: CollectorStatus, outcome: ScanOutcome, toolchain: Toolchain) -> CollectorRunInfo {
        var identity: (identity: String, label: String?)?
        if Self.toolchainIdentified.contains(status.name) {
            // The toolchain that ran the tests (coverage) or the T1 build
            // (`build`, design §1.8) is the tool, named by its own `swift
            // --version` (the swift on PATH may be swiftly's proxy, whose
            // hash names no compiler); diff also requires `swiftstats` to
            // match, since SwiftStats' own code maps the profiles, the
            // timings and the warnings.
            if status.state != .skipped, let reported = outcome.identities[status.name] {
                identity = (reported, nil)
            }
        } else if status.name == MutationAdapter.name {
            identity = mutationIdentity(for: status, outcome: outcome)
        } else if status.name == DependencyGraphAdapter.name {
            // The toolchain is the tool; diff also requires `swiftstats`
            // to match, since SwiftStats' own code reads the graph.
            if outcome.executables[status.name] != nil, let version = toolchain.swiftVersion {
                identity = ("swift:\(version)", nil)
            }
        } else if status.name == PeripheryAdapter.name {
            // outskirts is released by tag (design §1): the label adds
            // the tag naming the binary's commit, when there is one.
            if let executable = outcome.executables[status.name] {
                identity = BinaryIdentity.of(executable, tagged: true)
            }
        } else if let pinned = Self.linkedIdentities[status.name] {
            // Linked, not run as a binary: the pinned revision is the
            // build (SwiftEffectInference's, or indexstore-db's reader).
            // Diff also requires `swiftstats` to match, since SwiftStats'
            // own code maps the library's answers.
            if status.state != .skipped {
                identity = (pinned, nil)
            }
        } else if let executable = outcome.executables[status.name] {
            identity = BinaryIdentity.of(executable)
        }
        return CollectorRunInfo(
            name: status.name,
            state: status.state,
            reason: status.reason,
            version: status.version,
            identity: identity?.identity,
            identityLabel: identity?.label,
            options: status.options,
            durationMilliseconds: outcome.milliseconds[status.name] ?? 0
        )
    }

    /// The build identity of a SwiftMutator run recorded as `status` in
    /// `outcome`: the build its results file's header names made every
    /// result, and the resolved binary's commit labels it only when it is
    /// that build; a run that read no header is named by the binary.
    private static func mutationIdentity(
        for status: CollectorStatus,
        outcome: ScanOutcome
    ) -> (identity: String, label: String?)? {
        guard status.state != .skipped, let executable = outcome.executables[status.name] else {
            return nil
        }
        let binary = BinaryIdentity.of(executable)
        guard let reported = outcome.identities[status.name] else {
            return binary
        }
        return (reported, binary?.identity == reported ? binary?.label : nil)
    }

    /// The same scanner, its scans storing their snapshots as `added`
    /// says (`MutationSaving`).
    func saving(_ added: MutationSaving?) -> Self {
        Self(scanner: scanner.saving(added), build: build)
    }

    /// The same scanner, its scans recording in `record` the task log of a
    /// T1 build they ran that failed (`FailedBuildLog`).
    func recording(failedBuild record: FailedBuildLog?) -> Self {
        Self(scanner: scanner.recording(failedBuild: record), build: build)
    }

    /// The same scanner, its `index` collector reading the stores
    /// `factory` opens (`PackageScanner.readingIndex(with:)`).
    func readingIndex(
        with factory: @escaping @Sendable (_ store: URL, _ library: URL) throws -> any IndexStoreSource
    ) -> Self {
        Self(scanner: scanner.readingIndex(with: factory), build: build)
    }

    /// Scans the package at `root` with the configuration in
    /// `configurationFile` (or the default). `git` and `toolchain` are read
    /// when not given; a scan of an exported revision supplies its git state.
    /// Changes to the files at `ignoring` (relative to `root`, such as a
    /// store kept in the package) don't make the tree dirty. `history` says
    /// whether and where to read the history (PRD §7.13); the coverage
    /// collector, the T1 group and the SwiftMutator collector run only when
    /// `tiers` asks for them (M5–M7).
    public func scan(
        packageAt root: URL,
        configurationFile: URL?,
        git: GitState? = nil,
        ignoring: [String] = [],
        toolchain: Toolchain? = nil,
        date: Date = Date(),
        history: HistorySource = .automatic,
        tiers: RequestedTiers = .syntaxOnly
    ) throws -> ScannedSnapshot {
        let packageRoot = root.standardizedFileURL
        let gitState = git ?? GitReader.read(packageRoot: packageRoot, ignoring: ignoring)
        let scanned = try scanner.run(
            packageAt: packageRoot,
            configurationFile: configurationFile,
            tiers: tiers,
            git: gitState,
            ignoring: ignoring
        )
        let (outcome, historyRun) = Self.addHistory(
            to: scanned,
            source: history.resolved(packageRoot: packageRoot, git: gitState)
        )
        let tools = toolchain ?? ToolchainReader.read(packageRoot: packageRoot, tools: scanner.tools)
        let own = CollectorRunInfo(
            name: SwiftStatsCollector.name,
            state: .ran,
            reason: nil,
            version: SwiftStatsVersion.current,
            identity: build.identity,
            identityLabel: build.label,
            options: SwiftStatsCollector.options(
                configuration: outcome.configuration,
                metrics: outcome.report.metrics
            ),
            durationMilliseconds: outcome.milliseconds[SwiftStatsCollector.name] ?? 0
        )
        let external = outcome.report.collectors.map { status in
            status.name == HistoryCollector.name
                ? historyRun.info(status)
                : Self.info(for: status, outcome: outcome, toolchain: tools)
        }
        return ScannedSnapshot(
            info: SnapshotInfo(
                package: outcome.report.package,
                git: gitState,
                date: Self.format(date),
                toolchain: tools,
                collectors: (external + [own]).sorted { $0.name < $1.name }
            ),
            report: outcome.report
        )
    }
}
