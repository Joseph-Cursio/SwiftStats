//
//  MutationSession+Warnings.swift
//  SwiftStatsCore
//
//  The warnings a mutation step gives (M6, design §1.4, §2, §6.4), and
//  which of them describe the results a run stored rather than the run:
//  the lines of the results file that didn't read, why kills weren't
//  judged and the mapping's warnings, which a rescan carrying the results
//  keeps with them. A step gives the results' own warnings only for a run
//  that ran with results, so they never describe a file nothing kept.
//

extension MutationSession {
    /// What the warning about report keys that don't read says after
    /// their count.
    static let unreadableKeysText = " keys of swift-mutator report's JSON don't read, "
        + "so their kills aren't judged"

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
            || isUnreadableKeysWarning(warning) || MutationMapper.isMappingWarning(warning)
    }

    /// Whether `warning` is the one about report keys that don't read.
    private static func isUnreadableKeysWarning(_ warning: ScanWarning) -> Bool {
        warning.file == nil && warning.message.hasPrefix(MutationAdapter.name + ": ")
            && warning.message.hasSuffix(unreadableKeysText)
    }
}
