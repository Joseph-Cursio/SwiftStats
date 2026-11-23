//
//  MutationSession+Warnings.swift
//  SwiftStatsCore
//
//  The warnings a mutation step gives (M6, design §1.4, §2, §6.4), and
//  which of them describe the results a run stored rather than the run:
//  the lines of the results file that didn't read, why kills weren't
//  judged (the report failed, or has no entry for them) and the mapping's
//  warnings, which a rescan carrying the results keeps with them. A step
//  gives the results' own warnings only for a run that ran with results,
//  so they never describe a file nothing kept.
//

extension MutationSession {
    /// What the warning about kills the report has no entry for says
    /// before their count.
    private static let unreportedLead = "swift-mutator report's JSON has no entry that reads for "

    /// The warning that `count` kills by a failed test have no entry that
    /// reads in the report (its key doesn't read, or the report left the
    /// mutant out), so they aren't judged; nil when there are none.
    static func unreportedWarning(_ count: Int) -> ScanWarning? {
        guard count > 0 else {
            return nil
        }
        let kills = count == 1
            ? "1 kill by a failed test, so it isn't"
            : "\(count) kills by a failed test, so they aren't"
        return warning(unreportedLead + kills + " judged")
    }

    /// A scan warning, from the collector, saying `text`.
    static func warning(_ text: String) -> ScanWarning {
        ScanWarning(file: nil, message: "\(MutationAdapter.name): \(text)")
    }

    /// Whether `warning` describes the results a run stored, which carry
    /// it onto a rescan with them: the lines of their results file that
    /// didn't read, why their kills weren't judged, or the mapping's
    /// warnings.
    static func describesResults(_ warning: ScanWarning) -> Bool {
        MutationResults.isSkippedLinesWarning(warning) || MutationCommand.isUnjudgedWarning(warning)
            || isUnreportedWarning(warning) || MutationMapper.isMappingWarning(warning)
    }

    /// Whether `warning` is the one about kills the report has no entry
    /// for (`unreportedWarning`).
    private static func isUnreportedWarning(_ warning: ScanWarning) -> Bool {
        warning.file == nil && warning.message.hasPrefix(MutationAdapter.name + ": " + unreportedLead)
            && warning.message.hasSuffix(" judged")
    }
}
