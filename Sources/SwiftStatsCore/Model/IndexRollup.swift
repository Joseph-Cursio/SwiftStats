//
//  IndexRollup.swift
//  SwiftStatsCore
//
//  USRs and coupling counted over a module or a part of the project (M7,
//  design §3.4, §4.2, §4.3): the records with a primary USR, those without
//  one by the reason they have none (every reason listed, zero included),
//  those in a disagreement, the USR type cycles with a member in the scope
//  and its types in them, and the module edges starting in it. Every scope
//  has it, test modules included, since the index covers tests too; absent
//  when the `index` collector didn't run. Its metric names are
//  `index.withUSR`, `index.withoutUSR.<reason>`, `index.disagreements`,
//  `index.typeCycles`, `index.typesInCycles` and `index.moduleEdges`.
//

/// USR counts over one scope.
public struct IndexRollup: Codable, Hashable, Sendable {
    /// Records with a primary USR.
    public let withUSR: Int
    /// Records without one, by reason (`USRReason` raw values).
    public let withoutUSR: [String: Int]
    /// Records whose reason is a disagreement.
    public let disagreements: Int
    /// USR type cycles with a member in the scope (a part of the project:
    /// every cycle for production, none for tests, whose types the cycles
    /// leave out).
    public let typeCycles: Int
    /// The scope's types in a USR type cycle.
    public let typesInCycles: Int
    /// Module edges starting at a target of the scope.
    public let moduleEdges: Int

    /// The counts over `reasons`, each record's reason, nil for a record
    /// with a primary USR, with `cycles`, the numbers of the scope's types'
    /// cycles (one per type in a cycle), and `moduleEdges` edges.
    init(_ reasons: [USRReason?], cycles: [Int], moduleEdges: Int) {
        withUSR = reasons.count { $0 == nil }
        withoutUSR = Dictionary(uniqueKeysWithValues: USRReason.allCases.map { reason in
            (reason.rawValue, reasons.count { $0 == reason })
        })
        disagreements = reasons.count { $0 == .disagreement }
        typeCycles = Set(cycles).count
        typesInCycles = cycles.count
        self.moduleEdges = moduleEdges
    }
}
