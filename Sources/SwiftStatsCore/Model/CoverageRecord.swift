//
//  CoverageRecord.swift
//  SwiftStatsCore
//
//  One production function record's coverage (M5, PRD §7.8): its lines
//  and regions, and which test targets ran it. Null, never 0, for what
//  coverage can't say: a record no test bundle has code for carries a
//  reason instead, and a subscript whose accessors carry the coverage has
//  neither data nor a reason.
//

/// A production record's coverage.
public struct CoverageRecord: Codable, Hashable, Sendable {
    /// The record's key.
    public let key: String
    /// Its lines, by llvm-cov's per-function line rule over its own
    /// regions (closures folded in), less the lines of records nested in
    /// it on which none of its regions starts; nil without data.
    public let lines: CoverageTally?
    /// Its code regions, closures folded in, deduplicated by range with
    /// the largest count; nil without data.
    public let regions: CoverageTally?
    /// The test targets whose own test processes ran one of its entries,
    /// sorted; empty without data.
    public let testTargets: [String]
    /// Why it has no data: `no coverage data` (no test bundle holds code
    /// for it: an inactive `#if`, code no test links) or
    /// `not linked into any test bundle` (its module's files are all
    /// missing from the export); nil when it has data, and for a subscript
    /// container.
    public let reason: String?

    /// Creates a record's coverage. Fields are documented on their properties.
    public init(key: String, lines: CoverageTally?, regions: CoverageTally?, testTargets: [String], reason: String?) {
        self.key = key
        self.lines = lines
        self.regions = regions
        self.testTargets = testTargets
        self.reason = reason
    }
}
