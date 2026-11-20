//
//  EffectSummary.swift
//  SwiftStatsCore
//
//  What one SwiftEffectInference run produced beyond the per-record facts
//  (PRD §7.10): which revision ran, how many passes body inference took,
//  and the types whose construction refutes purity.
//

/// The outputs of one side-effect run.
public struct EffectSummary: Codable, Hashable, Sendable {
    /// The SwiftEffectInference revision SwiftStats links.
    public let revision: String
    /// Passes body inference ran, the last one confirming nothing changed.
    public let passes: Int
    /// Each type whose construction refutes purity, as `<type>: <reason>`,
    /// sorted by type.
    public let refutedTypes: [String]

    /// Creates a summary. Fields are documented on their properties.
    public init(revision: String, passes: Int, refutedTypes: [String]) {
        self.revision = revision
        self.passes = passes
        self.refutedTypes = refutedTypes
    }
}
