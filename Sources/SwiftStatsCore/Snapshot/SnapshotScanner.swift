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
        if status.name == CoverageAdapter.name {
            // The toolchain that ran the tests is the tool, named by its
            // own `swift --version` (the swift on PATH may be swiftly's
            // proxy, whose hash names no compiler); diff also requires
            // `swiftstats` to match, since SwiftStats' own code maps the
            // profiles.
            if status.state != .skipped, let reported = outcome.identities[status.name] {
                identity = (reported, nil)
            }
        } else if status.name == MutationAdapter.name {
            // The build its results file's header names made every result;
            // the resolved binary's commit labels it only when it is that
            // build. A run that read no header is named by the binary.
            if status.state != .skipped, let executable = outcome.executables[status.name] {
                let binary = BinaryIdentity.of(executable)
                if let reported = outcome.identities[status.name] {
                    identity = (reported, binary?.identity == reported ? binary?.label : nil)
                } else {
                    identity = binary
                }
            }
        } else if status.name == DependencyGraphAdapter.name {
            // The toolchain is the tool; diff also requires `swiftstats`
            // to match, since SwiftStats' own code reads the graph.
            if outcome.executables[status.name] != nil, let version = toolchain.swiftVersion {
                identity = ("swift:\(version)", nil)
            }
        } else if status.name == EffectCollector.name {
            // Linked, not run as a binary: the pinned revision is the
            // build. Diff also requires `swiftstats` to match, since
            // SwiftStats' own code maps the library's answers.
            if status.state != .skipped {
                identity = (EffectInferenceRevision.identity, nil)
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

    /// The same scanner, its scans storing their snapshots as `added`
    /// says (`MutationSaving`).
    func saving(_ added: MutationSaving?) -> Self {
        Self(scanner: scanner.saving(added), build: build)
    }

    /// Scans the package at `root` with the configuration in
    /// `configurationFile` (or the default). `git` and `toolchain` are read
    /// when not given; a scan of an exported revision supplies its git state.
    /// Changes to the files at `ignoring` (relative to `root`, such as a
    /// store kept in the package) don't make the tree dirty. `history` says
    /// whether and where to read the history (PRD §7.13); the coverage and
    /// SwiftMutator collectors run only when `tiers` asks for them (M5, M6).
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
