//
//  SitrepScanStats.swift
//  SwiftStatsCore
//
//  Sitrep's size figures, with Sitrep's field names.
//

/// Sitrep's `scanStats` block.
public struct SitrepScanStats: Codable, Hashable, Sendable {
    /// Files read.
    public let scannedFiles: Int
    /// Lines of all files joined end to end (Sitrep joins without a
    /// separator, so each file boundary merges two lines).
    public let totalLinesOfCode: Int
    /// Non-empty lines of all files joined end to end. Comments and lines of
    /// spaces count; Sitrep's comment stripper is disabled.
    public let totalStrippedLinesOfCode: Int
    /// The file with the most non-empty lines, by last path component.
    public let longestFile: SitrepStat?
    /// The type with the most non-empty lines, summed over its extensions.
    public let longestType: SitrepStat?
    /// Non-empty lines in UIKit classes, representables and their extensions.
    public let uiKitLinesOfCode: Int
    /// Non-empty lines in SwiftUI structs and their extensions.
    public let swiftUILinesOfCode: Int

    /// Creates the block. Fields are documented on their properties.
    public init(
        scannedFiles: Int,
        totalLinesOfCode: Int,
        totalStrippedLinesOfCode: Int,
        longestFile: SitrepStat?,
        longestType: SitrepStat?,
        uiKitLinesOfCode: Int,
        swiftUILinesOfCode: Int
    ) {
        self.scannedFiles = scannedFiles
        self.totalLinesOfCode = totalLinesOfCode
        self.totalStrippedLinesOfCode = totalStrippedLinesOfCode
        self.longestFile = longestFile
        self.longestType = longestType
        self.uiKitLinesOfCode = uiKitLinesOfCode
        self.swiftUILinesOfCode = swiftUILinesOfCode
    }
}
