//
//  SnapshotWorkspace+Export.swift
//  SwiftStatsCore
//
//  A scan of a past commit from an export (PRD §7.13, §10), shared by
//  `diff` and `backfill`. An old `.swift-version` can pin a toolchain that
//  is no longer installed or can't describe the manifest, whether it is
//  the package's own or, for a nested package, the one the export inherits
//  from above it; the export is scratch, so a failed scan is tried once
//  more without either pin.
//

import Foundation

extension SnapshotWorkspace {
    /// Exports `commit` of the package where `git` places it and scans it
    /// with `exportScanner`, reading history from `history`; the note says
    /// when the scan needed the export's toolchain pins removed.
    func scanExport(
        _ commit: String,
        git: GitState,
        scanner exportScanner: SnapshotScanner,
        history: HistorySource
    ) throws -> (snapshot: ScannedSnapshot, note: String?) {
        let exported = try RevisionExport.export(commit: commit, packagePath: git.packagePath, from: root)
        defer { ScratchRegistry.shared.remove(RevisionExport.workDirectory(of: exported)) }
        let state = GitState(commit: commit, branch: nil, isDirty: false, dirtyHash: nil, packagePath: git.packagePath)
        let scan = {
            try exportScanner.scan(
                packageAt: exported,
                configurationFile: self.configurationFile ?? StoreLocation.localConfiguration(packageRoot: exported),
                git: state,
                history: history
            )
        }
        do {
            return (try scan(), nil)
        } catch {
            let pins = RevisionExport.toolchainPins(of: exported)
            guard pins.isEmpty == false else {
                throw error
            }
            for pin in pins {
                try FileManager.default.removeItem(at: pin)
            }
            return (try scan(), "scanned without its .swift-version toolchain pin")
        }
    }
}
