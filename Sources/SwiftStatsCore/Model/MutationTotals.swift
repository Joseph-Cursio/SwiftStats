//
//  MutationTotals.swift
//  SwiftStatsCore
//
//  Every mutant a snapshot holds, counted (M6, design §3, §4): mapped,
//  dropped and unmapped alike, which is what SwiftMutator's own global
//  score and counts by outcome describe, not the production project's.
//

/// Every mutant, counted.
public struct MutationTotals: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes beside the counts.
    private enum CodingKeys: String, CodingKey {
        case dropped
        case unmapped
    }

    /// Every mutant by verdict.
    public let counts: MutationCounts
    /// How many were dropped by design.
    public let dropped: Int
    /// How many are in production files the mapping couldn't use.
    public let unmapped: Int

    /// Creates the totals. Fields are documented on their properties.
    public init(counts: MutationCounts, dropped: Int, unmapped: Int) {
        self.counts = counts
        self.dropped = dropped
        self.unmapped = unmapped
    }

    /// Reads the totals, the counts beside the other fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dropped = try container.decode(Int.self, forKey: .dropped)
        unmapped = try container.decode(Int.self, forKey: .unmapped)
        counts = try MutationCounts(from: decoder)
    }

    /// Writes the totals, the counts beside the other fields.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dropped, forKey: .dropped)
        try container.encode(unmapped, forKey: .unmapped)
        try counts.encode(to: encoder)
    }
}
