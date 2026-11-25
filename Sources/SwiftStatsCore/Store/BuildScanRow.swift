//
//  BuildScanRow.swift
//  SwiftStatsCore
//
//  The `buildScan` row (store v6, M7, design §6.4, §9.1): one per snapshot
//  holding the T1 build's results, with when the build ran, whether its
//  timings are complete, the totals, each class of entries the timings
//  left out with its entries and milliseconds, and the counts of lines
//  and warnings the build's output reading set aside. The per-record
//  timings are `function` columns, the type and file attachments
//  `timingAttachment` rows, and the warnings `finding` rows.
//

import GRDB

/// A snapshot's build results, as one row.
struct BuildScanRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "buildScan"

    /// The snapshot.
    var snapshotId: Int64
    /// When the build ran.
    var collectedAt: String
    /// Whether the timings are complete.
    var complete: Bool
    /// Function-body entries.
    var functionEntries: Int
    /// Expression entries.
    var expressionEntries: Int
    /// The total, records nested in a body left out.
    var totalMilliseconds: Int
    /// Entries with no location.
    var synthesizedEntries: Int
    /// Their milliseconds.
    var synthesizedMilliseconds: Int
    /// Entries in macro expansions.
    var macroEntries: Int
    /// Their milliseconds.
    var macroMilliseconds: Int
    /// Entries under the build directory.
    var buildEntries: Int
    /// Their milliseconds.
    var buildMilliseconds: Int
    /// Entries outside the package root.
    var outsideRootEntries: Int
    /// Their milliseconds.
    var outsideRootMilliseconds: Int
    /// Entries in files that changed during the scan.
    var fileChangedEntries: Int
    /// Their milliseconds.
    var fileChangedMilliseconds: Int
    /// Entries in files the scan didn't read.
    var unscannedEntries: Int
    /// Their milliseconds.
    var unscannedMilliseconds: Int
    /// Files that changed during the scan.
    var changedFiles: Int
    /// Timing-looking lines that didn't read.
    var unparsedTimingLines: Int
    /// Lines that held terminal escapes.
    var escapedLines: Int
    /// Other lines mentioning a warning.
    var otherWarningLines: Int
    /// Warnings dropped (build directory, outside the root).
    var warningsDropped: Int
    /// Warnings with no place.
    var warningsUnmapped: Int
    /// Warnings in plugin targets.
    var pluginWarnings: Int

    /// The row for `report`, collected at `collectedAt`, in snapshot
    /// `snapshotId`.
    init(_ report: BuildReport, collectedAt: String, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.collectedAt = collectedAt
        complete = report.complete
        functionEntries = report.totals.functionEntries
        expressionEntries = report.totals.expressionEntries
        totalMilliseconds = report.totals.milliseconds
        synthesizedEntries = report.unmapped.synthesized.entries
        synthesizedMilliseconds = report.unmapped.synthesized.milliseconds
        macroEntries = report.unmapped.macro.entries
        macroMilliseconds = report.unmapped.macro.milliseconds
        buildEntries = report.dropped.build.entries
        buildMilliseconds = report.dropped.build.milliseconds
        outsideRootEntries = report.dropped.outsideRoot.entries
        outsideRootMilliseconds = report.dropped.outsideRoot.milliseconds
        fileChangedEntries = report.dropped.fileChanged.entries
        fileChangedMilliseconds = report.dropped.fileChanged.milliseconds
        unscannedEntries = report.dropped.unscanned.entries
        unscannedMilliseconds = report.dropped.unscanned.milliseconds
        changedFiles = report.changedFiles
        unparsedTimingLines = report.unparsedTimingLines
        escapedLines = report.escapedLines
        otherWarningLines = report.otherWarningLines
        warningsDropped = report.warningsDropped
        warningsUnmapped = report.warningsUnmapped
        pluginWarnings = report.pluginWarnings
    }

    /// The report this row holds, with `records` and `attachments`.
    func report(records: [BuildRecordTiming], attachments: [BuildAttachment]) -> BuildReport {
        BuildReport(
            complete: complete,
            records: records,
            attachments: attachments,
            unmapped: BuildUnmapped(
                synthesized: BuildEntryCount(entries: synthesizedEntries, milliseconds: synthesizedMilliseconds),
                macro: BuildEntryCount(entries: macroEntries, milliseconds: macroMilliseconds)
            ),
            dropped: BuildDropped(
                build: BuildEntryCount(entries: buildEntries, milliseconds: buildMilliseconds),
                outsideRoot: BuildEntryCount(entries: outsideRootEntries, milliseconds: outsideRootMilliseconds),
                fileChanged: BuildEntryCount(entries: fileChangedEntries, milliseconds: fileChangedMilliseconds),
                unscanned: BuildEntryCount(entries: unscannedEntries, milliseconds: unscannedMilliseconds)
            ),
            totals: BuildTotals(
                functionEntries: functionEntries,
                expressionEntries: expressionEntries,
                milliseconds: totalMilliseconds
            ),
            changedFiles: changedFiles,
            unparsedTimingLines: unparsedTimingLines,
            escapedLines: escapedLines,
            otherWarningLines: otherWarningLines,
            warningsDropped: warningsDropped,
            warningsUnmapped: warningsUnmapped,
            pluginWarnings: pluginWarnings
        )
    }
}
