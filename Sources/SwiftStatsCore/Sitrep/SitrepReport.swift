//
//  SitrepReport.swift
//  SwiftStatsCore
//
//  The `sitrep` block of a scan (PRD §7.1): Sitrep's project counts, computed
//  by SwiftStats with Sitrep's rules and field names so `sitrep -f json` can
//  serve as a test oracle.
//

/// Sitrep-compatible project counts.
public struct SitrepReport: Codable, Hashable, Sendable {
    /// Size figures.
    public let scanStats: SitrepScanStats
    /// Type counts.
    public let objects: SitrepObjects
    /// Import statements per module, most imported first.
    public let imports: [SitrepStat]
    /// UIKit view controller, UIKit view and SwiftUI view counts.
    public let inheritances: [SitrepStat]

    /// Creates the block. Fields are documented on their properties.
    public init(scanStats: SitrepScanStats, objects: SitrepObjects, imports: [SitrepStat], inheritances: [SitrepStat]) {
        self.scanStats = scanStats
        self.objects = objects
        self.imports = imports
        self.inheritances = inheritances
    }
}
