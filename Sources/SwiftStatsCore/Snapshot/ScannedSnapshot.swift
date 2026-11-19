//
//  ScannedSnapshot.swift
//  SwiftStatsCore
//
//  A scan with its snapshot metadata, ready for the store.
//

/// A scan and its snapshot metadata.
public struct ScannedSnapshot: Hashable, Sendable {
    /// The metadata.
    public let info: SnapshotInfo
    /// The measurements.
    public let report: ScanReport

    /// Pairs metadata with the scan it describes.
    public init(info: SnapshotInfo, report: ScanReport) {
        self.info = info
        self.report = report
    }
}
