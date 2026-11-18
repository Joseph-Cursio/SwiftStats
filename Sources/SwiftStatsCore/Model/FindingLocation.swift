//
//  FindingLocation.swift
//  SwiftStatsCore
//
//  Where a finding is, and what that place attaches to (PRD §7.16).
//

/// One place a finding names.
public struct FindingLocation: Codable, Hashable, Sendable {
    /// Path relative to the package root.
    public let file: String
    /// 1-based line.
    public let line: Int
    /// 1-based column, when the tool gives one.
    public let column: Int?
    /// What the location attaches to.
    public let attachedTo: FindingTarget
    /// The function record's key, or `<module>::<type name>` for a type;
    /// nil for a file or a place outside the scan.
    public let owner: String?

    /// Creates a location. Fields are documented on their properties.
    public init(file: String, line: Int, column: Int?, attachedTo: FindingTarget, owner: String?) {
        self.file = file
        self.line = line
        self.column = column
        self.attachedTo = attachedTo
        self.owner = owner
    }
}
