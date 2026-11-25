//
//  BuildPlace.swift
//  SwiftStatsCore
//
//  A place the T1 build's output names (M7, design §6.1): a path as the
//  compiler printed it (an absolute real path, or a macro buffer's name),
//  a 1-based line and a 1-based UTF-8 column.
//

/// A path, line and column from the build's output.
struct BuildPlace: Hashable, Sendable {
    /// The path as printed.
    let path: String
    /// The 1-based line.
    let line: Int
    /// The 1-based UTF-8 column.
    let column: Int
}
