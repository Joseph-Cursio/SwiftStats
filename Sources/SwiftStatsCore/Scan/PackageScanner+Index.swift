//
//  PackageScanner+Index.swift
//  SwiftStatsCore
//
//  The T1 group's part of a scan (M7, design §1.7): the `build`, `index`
//  and `periphery` collectors. They run only when the scan asks for them
//  (`scan --index`), alone, once SwiftInferProperties, the coverage run and
//  the clone detector have finished and before SwiftMutator, since the
//  type-check timings are wall-clock and nothing else may compete for the
//  CPU. Every scan lists the three statuses. The build runs under the
//  group's lock, and everything that reads what it left is read before the
//  lock is released: its standard error and task log, read into type-check
//  timings mapped onto the records and compiler warnings as `swiftc`
//  findings (`BuildReport`). A collector reading the build is skipped
//  `needs the build: …` when the build didn't run, and fails when the
//  build wrote no index store. Once the build ran, the `index` collector
//  reads its store, joins its definitions to the records and counts its
//  references and coupling (`IndexAdapter`); until the outskirts
//  collector is built, `periphery` gives its placeholder once its own
//  settings let it run (design §13).
//

import Foundation

extension PackageScanner {
    /// The T1 group's part of a scan.
    struct IndexGroup {
        /// The `build` collector's run.
        let build: TimedAdapterResult
        /// The runs of the collectors that read the build, `index` and
        /// `periphery`, in that order.
        let readers: [TimedAdapterResult]
        /// The build's timings and warning counts mapped onto the scan;
        /// nil unless it ran and its output was read.
        let report: BuildReport?
        /// The build's warnings, as `swiftc` findings whose places aren't
        /// attached yet.
        let findings: [RawFinding]
        /// The index results mapped onto the scan; nil unless the `index`
        /// collector ran.
        let indexReport: IndexReport?

        /// The `index` collector's status.
        var indexStatus: CollectorStatus {
            readers[0].result.status
        }

        /// The three runs, `build`, `index` and `periphery`.
        var timed: [TimedAdapterResult] {
            [build] + readers
        }

        /// The tools whose findings the scan counts: `swiftc` when the
        /// build's output was read, even when it warned of nothing.
        var tools: [String] {
            report == nil ? [] : [WarningReader.tool]
        }

        /// A group in which each collector is skipped for `reason`.
        static func skipped(_ reason: String) -> Self {
            let runs = [BuildAdapter.name, IndexAdapter.name, PeripheryAdapter.name].map { name in
                TimedAdapterResult(
                    result: .skipped(name, reason: reason),
                    executable: nil,
                    identity: nil,
                    milliseconds: 0
                )
            }
            return Self(
                build: runs[0],
                readers: Array(runs.dropFirst()),
                report: nil,
                findings: [],
                indexReport: nil
            )
        }
    }

    /// A build run's output mapped onto a scan.
    struct MappedBuild {
        /// The run; failed when its output couldn't be read.
        let run: BuildRun
        /// The timings and warning counts; nil unless it ran and was read.
        let report: BuildReport?
        /// The warnings, as findings whose places aren't attached yet.
        let findings: [RawFinding]
    }

    /// The real path of `url`, symbolic links resolved (realpath(3)); its
    /// path when it can't be resolved.
    private static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else {
            return url.path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// `run`'s output mapped onto `measured`, the package at `root` with
    /// `targets`: its standard error and task log read (design §6.1), the
    /// timing entries placed on records, types and files (§6.2) and the
    /// warnings made findings (§6.3), against the root's real path and the
    /// build directory's. A run that didn't run maps to nothing; one whose
    /// output can't be read fails, saying so.
    static func build(
        of run: BuildRun,
        measured: ScanMeasurements,
        targets: [TargetSummary],
        root: URL
    ) -> MappedBuild {
        guard run.status.state == .ran, let products = run.products else {
            return MappedBuild(run: run, report: nil, findings: [])
        }
        let output: BuildOutput
        do {
            output = BuildOutputReader.read(
                stderr: try Data(contentsOf: products.stderr),
                log: try Data(contentsOf: products.log)
            )
        } catch {
            let replacements = [
                (products.scratch, CoverageCommand.buildPlaceholder), (root, CoverageCommand.packagePlaceholder)
            ]
            let reason = SwiftInferTargetRun.reason(for: error, replacing: replacements)
            let failed = run.failing("could not read the build's output: \(reason)")
            return MappedBuild(run: failed, report: nil, findings: [])
        }
        let rootPath = realPath(root)
        let changed = Set(products.changedFiles)
        let timings = TimingMapper(
            measured: measured,
            root: rootPath,
            build: products.scratch.path,
            changedFiles: changed
        ).map(output.entries)
        let warnings = WarningReader(
            measured: measured,
            targets: targets,
            root: rootPath,
            build: products.scratch.path,
            changedFiles: changed
        ).read(output.diagnostics)
        let report = BuildReport(
            output: output,
            timings: timings,
            warnings: warnings,
            changedFiles: changed.count,
            complete: products.complete
        )
        return MappedBuild(run: run, report: report, findings: warnings.findings)
    }

    /// The `periphery` collector's run on the package at `root` after
    /// `build`, under `configuration`: skipped for its own settings
    /// (`collectors.periphery.enabled`, a path that isn't an executable,
    /// no `outskirts` on PATH), else as the build leaves it, else the
    /// placeholder; outskirts never runs.
    private static func periphery(
        after build: BuildRun,
        root: URL,
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator
    ) -> AdapterResult {
        let resolution = ToolResolution.resolve(
            PeripheryAdapter.name,
            executable: PeripheryAdapter.executableName,
            configuration: configuration,
            locator: locator,
            root: root
        )
        if case .skip(let reason) = resolution {
            return .skipped(PeripheryAdapter.name, reason: reason)
        }
        return BuildAdapter.dependent(PeripheryAdapter.name, after: build)
            ?? .skipped(PeripheryAdapter.name, reason: PeripheryAdapter.notBuiltReason)
    }

    /// The `index` collector's run after `build`, under `configuration`,
    /// over `scan`: skipped for `collectors.index.enabled`, else as the
    /// build leaves it (`BuildAdapter.dependent`), else its read of the
    /// build's store.
    private func index(
        after build: BuildRun,
        configuration: SwiftStatsConfiguration,
        scan: IndexAdapter.Scan
    ) -> IndexAdapter.Run {
        let skipped: AdapterResult?
        if configuration.collectors[IndexAdapter.name]?.enabled == false {
            skipped = .skipped(IndexAdapter.name, reason: "disabled by collectors.\(IndexAdapter.name).enabled")
        } else {
            skipped = BuildAdapter.dependent(IndexAdapter.name, after: build)
        }
        guard skipped == nil, let products = build.products else {
            let result = skipped ?? .skipped(IndexAdapter.name, reason: BuildAdapter.notRequestedReason)
            return IndexAdapter.Run(
                timed: TimedAdapterResult(result: result, executable: nil, identity: nil, milliseconds: 0),
                report: nil
            )
        }
        return IndexAdapter.run(products: products, scan: scan, opening: indexSource)
    }

    /// The same scanner, its `index` collector reading the stores
    /// `factory` opens (tests pass recorded sources).
    func readingIndex(
        with factory: @escaping @Sendable (_ store: URL, _ library: URL) throws -> any IndexStoreSource
    ) -> Self {
        var scanner = self
        scanner.indexSource = factory
        return scanner
    }

    /// The T1 group's runs on the package at `root` under `configuration`,
    /// when the scan `requested` them: the build of `measured`'s package,
    /// whose `targets` its warnings are placed in, with its output mapped,
    /// then the `index` and `periphery` collectors as the build leaves
    /// them, all read under the group's lock. Each is skipped when the
    /// scan didn't ask for the group or the tools are skipped. A build
    /// that ran its command and failed, or whose output couldn't be read,
    /// records its task log in `failedBuild`.
    func runIndexGroup(
        root: URL,
        configuration: SwiftStatsConfiguration,
        requested: Bool,
        measured: ScanMeasurements,
        targets: [TargetSummary]
    ) -> IndexGroup {
        guard requested else {
            return .skipped(BuildAdapter.notRequestedReason)
        }
        if let toolSkipReason {
            return .skipped(toolSkipReason)
        }
        return CollectorRun.runBuild(
            root: root,
            configuration: configuration,
            locator: tools,
            measured: measured.files
        ) { run in
            let mapped = Self.build(of: run, measured: measured, targets: targets, root: root)
            failedBuild?.record(mapped.run)
            let index = index(
                after: mapped.run,
                configuration: configuration,
                scan: IndexAdapter.Scan(
                    root: root,
                    records: measured.records.sorted(by: Self.recordOrder),
                    types: measured.types,
                    files: measured.files,
                    targets: targets,
                    topLevelLines: measured.topLevelLines,
                    fileScopedTypes: measured.fileScopedTypes,
                    warnings: measured.warnings
                )
            )
            let periphery = Self.periphery(after: mapped.run, root: root, configuration: configuration, locator: tools)
            return IndexGroup(
                build: mapped.run.timed,
                readers: [
                    index.timed,
                    TimedAdapterResult(result: periphery, executable: nil, identity: nil, milliseconds: 0)
                ],
                report: mapped.report,
                findings: mapped.findings,
                indexReport: index.report
            )
        }
    }
}
