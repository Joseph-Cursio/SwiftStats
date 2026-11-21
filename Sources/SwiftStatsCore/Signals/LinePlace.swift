//
//  LinePlace.swift
//  SwiftStatsCore
//
//  A line of a file, so the coverage signals can count lines once.
//

/// A line of a file.
struct LinePlace: Hashable {
    /// The file.
    let file: String
    /// The line.
    let line: Int
}
