//
//  SitrepStat.swift
//  SwiftStatsCore
//
//  A named count, shaped like Sitrep's `Report.Stat` so the `sitrep` block
//  can be compared field by field with `sitrep -f json`.
//

/// A name and a count.
public struct SitrepStat: Codable, Hashable, Sendable {
    /// What is counted: a file, type or module name.
    public let name: String
    /// The count.
    public let value: Int

    /// Creates a stat.
    public init(name: String, value: Int) {
        self.name = name
        self.value = value
    }
}
