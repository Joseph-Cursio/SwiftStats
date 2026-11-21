//
//  CoverageLineRange.swift
//  SwiftStatsCore
//
//  Lines of a file inside an inactive `#if` branch of a function body,
//  which coverage skips (M5).
//

/// An inclusive range of lines.
public struct CoverageLineRange: Codable, Hashable, Sendable {
    /// The first line.
    public let start: Int
    /// The last line, inclusive.
    public let end: Int

    /// Creates a range. Fields are documented on their properties.
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}
