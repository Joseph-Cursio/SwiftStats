//
//  ScanWarning.swift
//  SwiftStatsCore
//
//  A problem that didn't stop the scan but that a reader should know about:
//  an unreadable file, or two declarations that produced the same key.
//

/// A non-fatal problem found during a scan.
public struct ScanWarning: Codable, Hashable, Sendable {
    /// The file concerned, relative to the package root, if any.
    public let file: String?
    /// What went wrong.
    public let message: String

    /// Creates a warning.
    public init(file: String?, message: String) {
        self.file = file
        self.message = message
    }
}
