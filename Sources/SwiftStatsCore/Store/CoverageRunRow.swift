//
//  CoverageRunRow.swift
//  SwiftStatsCore
//
//  The `coverageRun` table (store v4, M5): one row per snapshot holding
//  coverage, with when the tests ran, the test bundles, how the tests went,
//  the export's files dropped by design and where counts saturated.
//  `bundles` is newline-joined; `saturated` is a JSON array with sorted
//  keys and unescaped slashes.
//

import Foundation
import GRDB

/// A snapshot's coverage run.
struct CoverageRunRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "coverageRun"

    /// The snapshot.
    var snapshotId: Int64
    /// When the coverage was collected: the date of the scan that ran the
    /// tests, which a scan carrying it keeps.
    var collectedAt: String
    /// The test bundles, one per line.
    var bundles: String
    /// `passed` or `failing`.
    var tests: String
    /// Export files dropped under a build directory.
    var droppedBuild: Int
    /// Export files dropped outside the package root.
    var droppedOutsideRoot: Int
    /// Export files dropped in test targets.
    var droppedTestFiles: Int
    /// Export files dropped in no target of the package.
    var droppedOtherPackage: Int
    /// Where kept files hold saturated counts.
    var saturated: [CoverageSaturation]

    /// The bundles this row records.
    var bundleNames: [String] {
        bundles.split(separator: "\n").map(String.init)
    }

    /// The dropped files this row records.
    var dropped: CoverageDropped {
        CoverageDropped(
            build: droppedBuild,
            outsideRoot: droppedOutsideRoot,
            testFiles: droppedTestFiles,
            otherPackage: droppedOtherPackage
        )
    }

    /// The row for `report`, collected at `collectedAt`, in snapshot
    /// `snapshotId`.
    init(_ report: CoverageReport, collectedAt: String, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.collectedAt = collectedAt
        bundles = report.bundles.joined(separator: "\n")
        tests = report.tests
        droppedBuild = report.dropped.build
        droppedOutsideRoot = report.dropped.outsideRoot
        droppedTestFiles = report.dropped.testFiles
        droppedOtherPackage = report.dropped.otherPackage
        saturated = report.saturated
    }

    /// The encoder of the JSON columns: sorted keys and plain slashes, so
    /// the text is stable and readable.
    static func databaseJSONEncoder(for _: String) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
