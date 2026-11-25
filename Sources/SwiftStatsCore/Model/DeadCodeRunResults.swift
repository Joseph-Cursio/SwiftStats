//
//  DeadCodeRunResults.swift
//  SwiftStatsCore
//
//  How many results one outskirts run gave (M7, design §9.2's `runs`),
//  every class included.
//

/// One outskirts run's result count.
public struct DeadCodeRunResults: Codable, Hashable, Sendable {
    /// The run.
    public let name: DeadCodeRun
    /// Its entries, every class included.
    public let results: Int

    /// Creates a count. Fields are documented on their properties.
    public init(name: DeadCodeRun, results: Int) {
        self.name = name
        self.results = results
    }
}
