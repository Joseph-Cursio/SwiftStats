//
//  BuildReport+Sample.swift
//  SwiftStatsCoreTests
//
//  A hand-made build report for the report's type-check part (M7, design
//  §10.1): given records and attachments, an incomplete build with fixed
//  totals and distinct counts for every unmapped and dropped class, so a
//  test can tell each figure apart.
//

import Foundation
@testable import SwiftStatsCore

extension BuildReport {
    /// The sample's fixed figures, as the scan JSON writes them.
    private static let sampleJSON = """
        {
          "complete": false, "records": [], "attachments": [],
          "unmapped": {"synthesized": {"entries": 1, "milliseconds": 2}, "macro": {"entries": 3, "milliseconds": 4}},
          "dropped": {"build": {"entries": 5, "milliseconds": 6}, "outsideRoot": {"entries": 7, "milliseconds": 8},
                      "unscanned": {"entries": 9, "milliseconds": 10},
                      "fileChanged": {"entries": 11, "milliseconds": 12}},
          "totals": {"functionEntries": 4, "expressionEntries": 3, "milliseconds": 57},
          "changedFiles": 0, "unparsedTimingLines": 0, "escapedLines": 0, "otherWarningLines": 0,
          "warningsDropped": 0, "warningsUnmapped": 0, "pluginWarnings": 0
        }
        """

    /// An incomplete build holding `records` and `attachments`: 4
    /// function-body and 3 expression entries in all, 57 ms; synthesized
    /// 1 entry (2 ms), macro 3 (4 ms); dropped under the build directory
    /// 5 (6 ms), outside the root 7 (8 ms), unscanned 9 (10 ms), in changed
    /// files 11 (12 ms); no warnings dropped or unmapped.
    static func sample(records: [BuildRecordTiming], attachments: [BuildAttachment]) throws -> Self {
        let base = try JSONDecoder().decode(Self.self, from: Data(sampleJSON.utf8))
        return Self(
            complete: base.complete,
            records: records,
            attachments: attachments,
            unmapped: base.unmapped,
            dropped: base.dropped,
            totals: base.totals,
            changedFiles: base.changedFiles,
            unparsedTimingLines: base.unparsedTimingLines,
            escapedLines: base.escapedLines,
            otherWarningLines: base.otherWarningLines,
            warningsDropped: base.warningsDropped,
            warningsUnmapped: base.warningsUnmapped,
            pluginWarnings: base.pluginWarnings
        )
    }
}
