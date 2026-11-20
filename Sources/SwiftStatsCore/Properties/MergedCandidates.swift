//
//  MergedCandidates.swift
//  SwiftStatsCore
//
//  SwiftInferProperties' rows once every target's index is merged (PRD
//  §7.11), with what the merge dropped.
//

/// The merged rows and what the merge dropped.
struct MergedCandidates: Sendable {
    /// A kept row.
    struct Row: Sendable {
        /// The row.
        let row: SwiftInferRow
        /// Whether its identity was found at more than one location.
        let identityCollision: Bool
    }

    /// The kept rows, by population, identity, then location.
    let rows: [Row]
    /// Rows dropped as equal to a kept row but for timestamps.
    let duplicates: Int
    /// Rows dropped for a kept row at the same location with other fields.
    let conflicts: Int
    /// Identities kept at more than one location.
    let collisions: Int
}
