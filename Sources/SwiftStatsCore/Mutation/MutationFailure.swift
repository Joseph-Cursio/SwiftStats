//
//  MutationFailure.swift
//  SwiftStatsCore
//
//  Why reading SwiftMutator's output failed (M6, design §2). Its text is
//  the collector's reason, holding no path.
//

/// SwiftMutator output that couldn't be read, and why.
struct MutationFailure: Error, Equatable, CustomStringConvertible {
    /// The reason, without paths.
    let description: String
}
