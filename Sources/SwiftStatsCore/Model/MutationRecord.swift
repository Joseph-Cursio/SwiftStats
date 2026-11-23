//
//  MutationRecord.swift
//  SwiftStatsCore
//
//  One production record's mutants (M6, design §3, §4): counted by
//  verdict, and the tests named failing for its kills. Only records
//  holding at least one mutant are listed. Killing tests are names as
//  SwiftMutator records them, a lower bound: under fail-fast a kill names
//  at most the first failing test, and crash kills usually name none.
//

/// A record's mutants, counted.
public struct MutationRecord: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes beside the counts.
    private enum CodingKeys: String, CodingKey {
        case key
        case killingTests
    }

    /// The record's key.
    public let key: String
    /// Its mutants by verdict.
    public let counts: MutationCounts
    /// The distinct tests named failing for its kills, sorted.
    public let killingTests: [String]

    /// Creates a record's mutation figures. Fields are documented on their
    /// properties.
    public init(key: String, counts: MutationCounts, killingTests: [String]) {
        self.key = key
        self.counts = counts
        self.killingTests = killingTests
    }

    /// Reads the record, its counts beside its fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        killingTests = try container.decode([String].self, forKey: .killingTests)
        counts = try MutationCounts(from: decoder)
    }

    /// Writes the record, its counts beside its fields.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(killingTests, forKey: .killingTests)
        try counts.encode(to: encoder)
    }
}
