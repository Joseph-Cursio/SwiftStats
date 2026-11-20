//
//  PackageScanner+Clones.swift
//  SwiftStatsCore
//
//  The clone collector's part of a scan (PRD §7.12): SwiftCloneDetector
//  starts once the package is measured, since the files it reads leave out
//  those the scan marked generated, runs beside SwiftProjectLint and
//  SwiftLint, and its classes are attached to the measured records. The
//  tools' skip reason covers it too.
//

import Foundation

extension PackageScanner {
    /// The classes of `run` merged and attached to `measured`'s records;
    /// nil unless it ran.
    static func clones(of run: CloneRun, measured: ScanMeasurements) -> CloneMapping? {
        CloneMapper(measured: measured).mapping(of: run)
    }

    /// SwiftCloneDetector's runs over the production files of `targets`
    /// that `measured` read and doesn't mark generated, in the package at
    /// `root`, started in the background; nil when the tools are skipped.
    func startClones(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        measured: ScanMeasurements
    ) -> BackgroundJob<CloneRun>? {
        guard toolSkipReason == nil else {
            return nil
        }
        return CollectorRun.startClones(
            root: root,
            files: SwiftCloneDetectorAdapter.files(of: targets, read: measured.files),
            configuration: configuration,
            locator: tools
        )
    }
}
