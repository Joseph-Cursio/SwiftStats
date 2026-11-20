//
//  EffectRollup.swift
//  SwiftStatsCore
//
//  Side-effect counts over a production module or the project's production
//  part (PRD §7.10): records by resolved tier and by purity verdict. Absent
//  from a roll-up when SwiftEffectInference didn't run, and from test
//  modules and the `tests` part, whose records get no facts.
//

/// Side-effect facts counted over one scope.
public struct EffectRollup: Codable, Hashable, Sendable {
    /// Records by resolved tier (`EffectFacts.Tier` raw values); records
    /// with no tier aren't counted.
    public let tier: [String: Int]
    /// Records by purity verdict (`EffectFacts.Purity` raw values).
    public let purity: [String: Int]

    /// The counts over `records`' side-effect facts; records without facts
    /// aren't counted.
    init(_ records: [FunctionRecord]) {
        let facts = records.compactMap(\.effect)
        tier = facts.compactMap(\.tier).reduce(into: [:]) { counts, tier in
            counts[tier.rawValue, default: 0] += 1
        }
        purity = facts.reduce(into: [:]) { counts, fact in
            counts[fact.purity.rawValue, default: 0] += 1
        }
    }
}
