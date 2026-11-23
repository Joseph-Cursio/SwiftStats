//
//  FileRecord.swift
//  SwiftStatsCore
//
//  One row per scanned file (PRD §7.2): its length, and the SHA-256 of its
//  bytes, which SwiftMutator's results are matched against (M6).
//

/// A scanned source file, its length and its content hash.
public struct FileRecord: Codable, Hashable, Sendable {
    /// Path of the file, relative to the package root.
    public let path: String
    /// The target (module) the file belongs to.
    public let module: String
    /// Physical lines.
    public let lines: Int
    /// Lines that hold at least one token, comments, whitespace and
    /// attributes excluded (PRD §7.2).
    public let strippedLines: Int
    /// Whether the file is generated: a `generated` glob matches its path,
    /// or its leading comment carries a known header (PRD D8).
    public let generated: Bool
    /// SHA-256 of the file's bytes as read, a UTF-8 byte order mark
    /// included, in lowercase hex: what SwiftMutator records as a mutant's
    /// `fileSHA256` for the same bytes (M6, design §3).
    public let sha256: String

    /// Creates a record. Fields are documented on their properties.
    public init(path: String, module: String, lines: Int, strippedLines: Int, generated: Bool, sha256: String) {
        self.path = path
        self.module = module
        self.lines = lines
        self.strippedLines = strippedLines
        self.generated = generated
        self.sha256 = sha256
    }
}
