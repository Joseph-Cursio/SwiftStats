//
//  ProcessEnvironment.swift
//  SwiftStatsCore
//
//  How a command's environment differs from this process's: variables
//  removed (the mutation collector's copy runs git without the ones that
//  name a repository, M6) and variables added.
//

import Foundation

/// The changes a command's environment makes to this process's.
struct ProcessEnvironment {
    /// This process's environment, unchanged.
    static let inherited = Self(added: [:], removed: [])

    /// The variables added, each replacing any of its name.
    let added: [String: String]
    /// The names of the variables removed.
    let removed: Set<String>

    /// Whether it changes nothing.
    var isInherited: Bool {
        added.isEmpty && removed.isEmpty
    }

    /// The whole environment: `base` without `removed`, with `added`.
    func applied(to base: [String: String]) -> [String: String] {
        base.filter { removed.contains($0.key) == false }.merging(added) { $1 }
    }
}
