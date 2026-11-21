//
//  PackageScanner+Coverage.swift
//  SwiftStatsCore
//
//  The coverage collector's part of a scan (M5). It runs only when the
//  scan asks for it (`scan --coverage`), and starts once the targets are
//  resolved, since it needs only the package's files, so it runs while the
//  package is measured. The tools' skip reason covers a requested run.
//  Once the package is measured, a run that ran is mapped onto its
//  records, the unmapped entries' names demangled by the run's toolchain,
//  and passed through the store's rows (`CoverageRows`), so the scan JSON
//  is what a carried copy would give.
//

import Foundation

extension PackageScanner {
    /// The warning when the unmapped entries' names couldn't be demangled.
    static let undemangledWarning = ScanWarning(
        file: nil,
        message: "coverage: `swift demangle` failed, so unmapped entries are listed without demangled names"
    )

    /// The warnings mapping coverage can give, which describe the coverage
    /// and so go with it when a rescan carries it (`CoverageCarry`).
    static let coverageMappingWarnings: Set<ScanWarning> = [undemangledWarning]

    /// `run`'s export mapped onto `measured`, the package at `root` with
    /// `targets` and `configuration`, as the store's rows hold it; nil
    /// unless it ran. The warning says when the unmapped entries' names
    /// couldn't be demangled.
    static func coverage(
        of run: CoverageRun,
        measured: ScanMeasurements,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        root: URL
    ) -> (report: CoverageReport?, warnings: [ScanWarning]) {
        guard run.status.state == .ran, let export = run.export, let profiles = run.profiles else {
            return (nil, [])
        }
        let mapper = CoverageMapper(
            measured: measured,
            targets: targets,
            root: root,
            excluded: configuration.excluded.map(GlobPattern.init)
        )
        var warnings: [ScanWarning] = []
        let report = mapper.report(of: export, profiles: profiles) { names in
            guard names.isEmpty == false, let swift = run.executable else {
                return [:]
            }
            do {
                return try CoverageDemangler.demangled(names, swift: swift, root: root)
            } catch {
                warnings.append(Self.undemangledWarning)
                return [:]
            }
        }
        return (CoverageRows.normalized(report), warnings)
    }

    /// The coverage collector's run on the package at `root`, started in
    /// the background; a skip, already finished, when it wasn't
    /// `requested` or the tools are skipped.
    func startCoverage(
        root: URL,
        configuration: SwiftStatsConfiguration,
        requested: Bool
    ) -> BackgroundJob<CoverageRun> {
        guard requested else {
            return BackgroundJob(finished: .skipped(CoverageAdapter.notRequestedReason))
        }
        if let toolSkipReason {
            return BackgroundJob(finished: .skipped(toolSkipReason))
        }
        return CollectorRun.startCoverage(root: root, configuration: configuration, locator: tools)
    }
}
