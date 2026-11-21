//
//  CoverageSaturation.swift
//  SwiftStatsCore
//
//  Where a kept file holds a saturated count (M5): `Int64.max` or more,
//  from counter updates lost in parallel test processes. It reads as
//  covered.
//

/// A line holding a saturated count.
public struct CoverageSaturation: Codable, Hashable, Sendable {
    /// Path of the file, relative to the package root.
    public let file: String
    /// The line a saturated region or segment starts on.
    public let line: Int

    /// Creates a place. Fields are documented on their properties.
    public init(file: String, line: Int) {
        self.file = file
        self.line = line
    }
}
