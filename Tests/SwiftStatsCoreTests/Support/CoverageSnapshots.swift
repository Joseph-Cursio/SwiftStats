//
//  CoverageSnapshots.swift
//  SwiftStatsCoreTests
//
//  Snapshots with coverage made to order (M5): a scanned snapshot given
//  other coverage, another coverage run or another git state, its roll-ups
//  rebuilt as a scan builds them, so the store, diff and trend can be
//  checked without running the coverage collector again.
//

@testable import SwiftStatsCore

/// Builds snapshots with chosen coverage.
enum CoverageSnapshots {
    /// The coverage run of a plain scan, which skips it.
    static let skipped = CollectorRunInfo(
        name: CoverageAdapter.name,
        state: .skipped,
        reason: CoverageAdapter.notRequestedReason,
        version: nil,
        identity: nil,
        identityLabel: nil,
        options: [],
        durationMilliseconds: 0
    )

    /// A coverage run that ran with `options`.
    static func ran(options: [String]) -> CollectorRunInfo {
        CollectorRunInfo(
            name: CoverageAdapter.name,
            state: .ran,
            reason: nil,
            version: "LLVM version 21.0.0",
            identity: "swift:test swift",
            identityLabel: nil,
            options: options,
            durationMilliseconds: 0
        )
    }

    /// `snapshot` at `git`, with `coverage` as its coverage and `run` as its
    /// coverage run, and its roll-ups' coverage rebuilt from them.
    static func replacing(
        _ snapshot: ScannedSnapshot,
        git: GitState,
        coverage: CoverageReport?,
        run: CollectorRunInfo
    ) -> ScannedSnapshot {
        replacing(snapshot, git: git, coverage: coverage, run: run, warnings: [])
    }

    /// `snapshot` at `git`, with `coverage` as its coverage, `run` as its
    /// coverage run and `warnings` added to its own, and its roll-ups'
    /// coverage rebuilt from them.
    static func replacing(
        _ snapshot: ScannedSnapshot,
        git: GitState,
        coverage: CoverageReport?,
        run: CollectorRunInfo,
        warnings: [ScanWarning]
    ) -> ScannedSnapshot {
        let old = snapshot.report
        let plain = old.rollups.map { $0.with(coverage: nil) }
        let rollups = coverage.map { report in
            CoverageRollupBuilder(targets: old.targets, records: old.records, coverage: report).rollups(plain)
        } ?? plain
        let status = CollectorStatus(
            name: run.name,
            state: run.state,
            version: run.version,
            reason: run.reason,
            options: run.options
        )
        var report = ScanReport(
            schemaVersion: old.schemaVersion,
            tool: old.tool,
            metrics: old.metrics,
            package: old.package,
            configuration: old.configuration,
            targets: old.targets,
            records: old.records,
            types: old.types,
            files: old.files,
            rollups: rollups,
            sitrep: old.sitrep,
            collectors: (old.collectors.filter { $0.name != run.name } + [status]).sorted { $0.name < $1.name },
            findings: old.findings,
            tests: old.tests,
            dependencies: old.dependencies,
            warnings: (old.warnings + warnings).sorted(by: PackageScanner.warningOrder),
            effects: old.effects,
            properties: old.properties,
            clones: old.clones,
            laws: old.laws,
            coverage: coverage,
            mutation: nil
        )
        report.history = old.history
        let info = SnapshotInfo(
            package: snapshot.info.package,
            git: git,
            date: snapshot.info.date,
            toolchain: snapshot.info.toolchain,
            collectors: (snapshot.info.collectors.filter { $0.name != run.name } + [run]).sorted { $0.name < $1.name }
        )
        return ScannedSnapshot(info: info, report: report)
    }

    /// `report` with the record `key`'s lines and regions replaced.
    static func changing(
        _ report: CoverageReport,
        key: String,
        lines: CoverageTally?,
        regions: CoverageTally?
    ) -> CoverageReport {
        CoverageReport(
            records: report.records.map { record in
                guard record.key == key else {
                    return record
                }
                return CoverageRecord(
                    key: key,
                    lines: lines,
                    regions: regions,
                    testTargets: record.testTargets,
                    reason: record.reason,
                    link: record.link,
                    linkedTests: record.linkedTests
                )
            },
            attachments: report.attachments,
            unmapped: report.unmapped,
            dropped: report.dropped,
            bundles: report.bundles,
            tests: report.tests,
            saturated: report.saturated,
            files: report.files
        )
    }

    /// `report` with `bundles` as its test bundles.
    static func with(bundles: [String], in report: CoverageReport) -> CoverageReport {
        CoverageReport(
            records: report.records,
            attachments: report.attachments,
            unmapped: report.unmapped,
            dropped: report.dropped,
            bundles: bundles,
            tests: report.tests,
            saturated: report.saturated,
            files: report.files
        )
    }
}
