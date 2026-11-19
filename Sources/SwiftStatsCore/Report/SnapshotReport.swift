//
//  SnapshotReport.swift
//  SwiftStatsCore
//
//  `swiftstats report --format json` (PRD §10): a snapshot's metadata and
//  its scan report. It has its own `schemaVersion`; the scan report inside
//  keeps its own.
//

/// A stored snapshot, as `report` writes it.
public struct SnapshotReport: Codable, Hashable, Sendable {
    /// The version of this document's format.
    public static let currentSchemaVersion = 1

    /// The document's format version.
    public let schemaVersion: Int
    /// Which state of which package, when, and each collector's run.
    public let snapshot: SnapshotInfo
    /// The measurements.
    public let scan: ScanReport

    /// The report of `snapshot` and its `scan`.
    public init(snapshot: SnapshotInfo, scan: ScanReport) {
        schemaVersion = Self.currentSchemaVersion
        self.snapshot = snapshot
        self.scan = scan
    }
}
