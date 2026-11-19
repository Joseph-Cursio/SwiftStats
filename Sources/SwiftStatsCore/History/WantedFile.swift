//
//  WantedFile.swift
//  SwiftStatsCore
//
//  One version of a file history has to parse: a blob at a path, with the module
//  and test-ness of the path.
//

/// A file version to parse.
struct WantedFile: Sendable {
    /// The blob holding the version.
    let blob: String
    /// The path, relative to the package root.
    let path: String
    /// The module the path belongs to.
    let module: String
    /// Whether the path is test code.
    let isTest: Bool
}
