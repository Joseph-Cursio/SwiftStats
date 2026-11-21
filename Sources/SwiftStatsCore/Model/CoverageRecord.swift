//
//  CoverageRecord.swift
//  SwiftStatsCore
//
//  One production function record's coverage (M5, PRD §7.8): its lines
//  and regions, which test targets ran it, and for a public function the
//  link rule and how many tests it links (a heuristic). Null, never 0, for
//  what coverage can't say: a record no test bundle has code for carries a
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
    /// For a public function (a production, non-generated `public` or
    /// `open` function, initialiser or accessor, or a subscript that is
    /// no container), the rule its tests are counted by; nil for any
    /// other record.
    public let link: CoverageLink?
    /// The tests linked to a public function: those whose target ran it
    /// (`testTargets`) and that name it by its `link` rule; nil
    /// without data, for a witness, and for any other record.
    public let linkedTests: Int?

    /// Creates a record's coverage. Fields are documented on their properties.
    public init(
        key: String,
        lines: CoverageTally?,
        regions: CoverageTally?,
        testTargets: [String],
        reason: String?,
        link: CoverageLink?,
        linkedTests: Int?
    ) {
        self.key = key
        self.lines = lines
        self.regions = regions
        self.testTargets = testTargets
        self.reason = reason
        self.link = link
        self.linkedTests = linkedTests
    }
}
