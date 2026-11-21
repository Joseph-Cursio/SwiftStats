//
//  CoverageLineRange.swift
//  SwiftStatsCore
//
//  Lines of a file inside an inactive `#if` branch of a function body,
//  which coverage skips (M5), or top-level statements the compiler didn't
//  compile.
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

    /// The fewest ranges covering exactly `lines`, in order.
    static func ranges(covering lines: Set<Int>) -> [Self] {
        var ranges: [Self] = []
        for line in lines.sorted() {
            if let last = ranges.last, last.end + 1 == line {
                ranges[ranges.count - 1] = Self(start: last.start, end: line)
            } else {
                ranges.append(Self(start: line, end: line))
            }
        }
        return ranges
    }
}
