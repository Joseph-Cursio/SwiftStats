//
//  BuildReport.swift
//  SwiftStatsCore
//
//  What the `build` collector's T1 build gave, mapped onto the scan (M7,
//  design §6, §9.2): each record's type-check time and slowest expression,
//  the time attached to types and files, the timing entries left unmapped
//  (synthesized members, macro expansions) or dropped (the build directory,
//  outside the root, files changed during the scan, files not parsed), the
//  totals, and the counters the independent checker accounts for. The
//  compiler's warnings are the scan's `swiftc` findings; this block counts
//  the ones dropped, unmapped and in plugin targets. Absent when the
//  collector didn't run.
//

/// A snapshot's T1 build results, mapped to records.
public struct BuildReport: Codable, Hashable, Sendable {
    /// Whether the build re-timed every root file: false when the run
    /// found no root intermediates to remove before building, so files it
    /// didn't recompile have no timings.
    public let complete: Bool
    /// The records holding a timing entry, by key.
    public let records: [BuildRecordTiming]
    /// The types and files holding a timing entry, by what they attach to,
    /// then owner.
    public let attachments: [BuildAttachment]
    /// The timing entries no position in the package holds.
    public let unmapped: BuildUnmapped
    /// The timing entries left out.
    public let dropped: BuildDropped
    /// The timing totals.
    public let totals: BuildTotals
    /// How many scanned files changed during the scan.
    public let changedFiles: Int
    /// Lines of the standard error holding `ms<TAB>` that state no timing
    /// entry (expected 0).
    public let unparsedTimingLines: Int
    /// Lines of the build's output that held an escape sequence.
    public let escapedLines: Int
    /// Lines starting `warning: ` that aren't diagnostics.
    public let otherWarningLines: Int
    /// Distinct warnings dropped: under the build directory or outside the
    /// root.
    public let warningsDropped: Int
    /// Distinct warnings left unmapped: in a macro expansion without its
    /// origin note, at `<unknown>`, or in a file that changed during the
    /// scan.
    public let warningsUnmapped: Int
    /// Distinct warnings in a plugin target (findings too).
    public let pluginWarnings: Int

    /// Creates a report. Fields are documented on their properties.
    public init(
        complete: Bool,
        records: [BuildRecordTiming],
        attachments: [BuildAttachment],
        unmapped: BuildUnmapped,
        dropped: BuildDropped,
        totals: BuildTotals,
        changedFiles: Int,
        unparsedTimingLines: Int,
        escapedLines: Int,
        otherWarningLines: Int,
        warningsDropped: Int,
        warningsUnmapped: Int,
        pluginWarnings: Int
    ) {
        self.complete = complete
        self.records = records
        self.attachments = attachments
        self.unmapped = unmapped
        self.dropped = dropped
        self.totals = totals
        self.changedFiles = changedFiles
        self.unparsedTimingLines = unparsedTimingLines
        self.escapedLines = escapedLines
        self.otherWarningLines = otherWarningLines
        self.warningsDropped = warningsDropped
        self.warningsUnmapped = warningsUnmapped
        self.pluginWarnings = pluginWarnings
    }

    /// The report of a build whose output read as `output`, whose timings
    /// mapped as `timings` and whose warnings read as `warnings`, with
    /// `changedFiles` scanned files changed during the scan.
    init(
        output: BuildOutput,
        timings: TimingMapper.Mapped,
        warnings: WarningReader.Read,
        changedFiles: Int,
        complete: Bool
    ) {
        self.init(
            complete: complete,
            records: timings.records,
            attachments: timings.attachments,
            unmapped: timings.unmapped,
            dropped: timings.dropped,
            totals: timings.totals,
            changedFiles: changedFiles,
            unparsedTimingLines: output.unparsedTimingLines,
            escapedLines: output.escapedLines,
            otherWarningLines: output.otherWarningLines,
            warningsDropped: warnings.dropped,
            warningsUnmapped: warnings.unmapped,
            pluginWarnings: warnings.plugin
        )
    }
}
