//
//  CloneInstance.swift
//  SwiftStatsCore
//
//  One copy in a clone class (PRD §7.12): where it is, with an inclusive
//  end, how many stripped lines it covers, and the function records it
//  sits in or covers whole, so later steps can speak in records and
//  families rather than line ranges.
//

/// One copy of cloned code.
public struct CloneInstance: Codable, Hashable, Sendable {
    /// Path of the file, relative to the package root.
    public let file: String
    /// The copy's range, both ends inclusive: SwiftCloneDetector's
    /// exclusive end column is moved back by one, and a column on the first
    /// line of a file starting with a byte order mark is moved on by its
    /// three bytes, as records' columns are, or kept at `Int.max` when that
    /// would carry it past the largest integer.
    public let range: SourceSpan
    /// Lines in `range` that hold a token, attributes excluded, as a
    /// record's stripped lines are counted (PRD §7.2).
    public let strippedLines: Int
    /// Key of the innermost function record whose range holds the copy,
    /// the record itself when the copy is a whole function; nil when no
    /// record holds it, as for a whole type.
    public let containing: String?
    /// Keys of the function records the copy covers whole, nested ones
    /// included, in source order.
    public let wholes: [String]

    /// Creates an instance. Fields are documented on their properties.
    public init(file: String, range: SourceSpan, strippedLines: Int, containing: String?, wholes: [String]) {
        self.file = file
        self.range = range
        self.strippedLines = strippedLines
        self.containing = containing
        self.wholes = wholes
    }
}
