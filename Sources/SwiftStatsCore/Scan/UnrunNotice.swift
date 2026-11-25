//
//  UnrunNotice.swift
//  SwiftStatsCore
//
//  What `scan` prints on standard error about an opt-in collector it was
//  asked for (`--coverage`, `--index`, `--mutation`) that collected nothing
//  this scan: it failed, was refused (a SwiftMutator run an earlier scan
//  started still running, M6; another `scan --index` holding the T1
//  group's lock, M7) or was skipped (the tool not found, or turned off).
//  For `--index` the line is about the T1 build, which the index read and
//  outskirts need.
//  The scan still stores its snapshot and exits 0, as a failed coverage
//  run always has (M5): the snapshot keeps the results of the one it
//  replaces when they still describe the tree, or holds none, and the
//  collector's state and reason are in the scan JSON. Without this line
//  the terminal said only that a snapshot was stored. When the results
//  were carried, the collector reads `ran` (carried), and the line is the
//  carry's own warning, which says what became of this scan's run and
//  which results it keeps; otherwise it says how the run ended, in the
//  carry's words.
//

import Foundation

/// The lines `scan` prints about the opt-in runs it asked for that
/// collected nothing.
public enum UnrunNotice {
    /// An opt-in collector and how the carry words what became of its run.
    private struct OptIn {
        /// The collector's name.
        let name: String
        /// What the carry's words start with, before `failed` or `was
        /// skipped`.
        let lead: String
        /// What became of a run that ended as a state for a reason, in the
        /// carry's words; nil when it ran.
        let ownRun: (CollectorState, String?) -> String?
    }

    /// What each line starts with.
    static let lead = "Warning: "

    /// The lines for `report`, a scan that asked for `requested`, one for
    /// each opt-in collector it asked for that collected nothing, in the
    /// order the collectors run (coverage, the T1 build, then
    /// SwiftMutator); none when each ran.
    public static func lines(for report: ScanReport, requested: RequestedTiers) -> [String] {
        var asked: [OptIn] = []
        if requested.coverage {
            asked.append(OptIn(
                name: CoverageAdapter.name,
                lead: CoverageCarry.ownRunLead,
                ownRun: CoverageCarry.ownRun(state:reason:)
            ))
        }
        if requested.index {
            asked.append(OptIn(
                name: BuildAdapter.name,
                lead: BuildAdapter.ownRunLead,
                ownRun: BuildAdapter.ownRun(state:reason:)
            ))
        }
        if requested.mutation != nil {
            asked.append(OptIn(
                name: MutationAdapter.name,
                lead: MutationCarry.ownRunLead,
                ownRun: MutationCarry.ownRun(state:reason:)
            ))
        }
        return asked.flatMap { collector -> [String] in
            guard let status = report.collectors.first(where: { $0.name == collector.name }) else {
                return []
            }
            if let what = collector.ownRun(status.state, status.reason) {
                return [lead + "\(collector.name): \(what)"]
            }
            let carried = "\(collector.name): \(collector.lead)"
            return report.warnings.filter { $0.file == nil && $0.message.hasPrefix(carried) }
                .map { lead + $0.message }
        }
    }
}
