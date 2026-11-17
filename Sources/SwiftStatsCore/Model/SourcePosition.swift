//
//  SourcePosition.swift
//  SwiftStatsCore
//
//  A 1-based line and column, the unit every external tool reports locations
//  in (coverage, mutants, linters), so results can be mapped back to records.
//

/// A 1-based line and UTF-8 column within a source file.
public struct SourcePosition: Codable, Hashable, Comparable, Sendable {
    /// 1-based line number.
    public let line: Int
    /// 1-based UTF-8 column.
    public let column: Int

    /// Creates a position from a 1-based line and column.
    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    /// Source order: by line, then by column.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }
        return lhs.column < rhs.column
    }
}
