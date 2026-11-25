//
//  IndexRollup.swift
//  SwiftStatsCore
//
//  USRs counted over a module or a part of the project (M7, design §3.4):
//  the records with a primary USR, those without one by the reason they
//  have none (every reason listed, zero included), and those in a
//  disagreement. Every scope has it, test modules included, since the
//  index covers tests too; absent when the `index` collector didn't run.
//  Its metric names are `index.withUSR`, `index.withoutUSR.<reason>` and
//  `index.disagreements`.
//

/// USR counts over one scope.
public struct IndexRollup: Codable, Hashable, Sendable {
    /// Records with a primary USR.
    public let withUSR: Int
    /// Records without one, by reason (`USRReason` raw values).
    public let withoutUSR: [String: Int]
    /// Records whose reason is a disagreement.
    public let disagreements: Int

    /// The counts over `reasons`, each record's reason, nil for a record
    /// with a primary USR.
    init(_ reasons: [USRReason?]) {
        withUSR = reasons.count { $0 == nil }
        withoutUSR = Dictionary(uniqueKeysWithValues: USRReason.allCases.map { reason in
            (reason.rawValue, reasons.count { $0 == reason })
        })
        disagreements = reasons.count { $0 == .disagreement }
    }
}
