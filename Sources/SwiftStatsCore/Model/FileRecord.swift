//
//  FileRecord.swift
//  SwiftStatsCore
//
//  One row per scanned file (PRD §7.2): its length.
//

/// A scanned source file and its length.
public struct FileRecord: Codable, Hashable, Sendable {
    /// Path of the file, relative to the package root.
    public let path: String
    /// The target (module) the file belongs to.
    public let module: String
    /// Physical lines.
    public let lines: Int
    /// Lines that hold at least one token, comments and whitespace excluded.
    public let strippedLines: Int

    /// Creates a record. Fields are documented on their properties.
    public init(path: String, module: String, lines: Int, strippedLines: Int) {
        self.path = path
        self.module = module
        self.lines = lines
        self.strippedLines = strippedLines
    }
}
