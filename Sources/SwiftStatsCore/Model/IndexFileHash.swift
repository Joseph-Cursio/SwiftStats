//
//  IndexFileHash.swift
//  SwiftStatsCore
//
//  A scanned file's SHA-256 as the T1 build left it (M7, design §1.3 step
//  9, §9.1): hashed again after the build, so a later carry can tell an
//  edit the dirty hash misses.
//

/// A scanned file and its hash after the build.
public struct IndexFileHash: Codable, Hashable, Sendable {
    /// The file, relative to the package root.
    public let path: String
    /// The hex SHA-256 of its bytes after the build; nil when it could no
    /// longer be read.
    public let sha256: String?

    /// Creates the entry. Fields are documented on their properties.
    public init(path: String, sha256: String?) {
        self.path = path
        self.sha256 = sha256
    }
}
