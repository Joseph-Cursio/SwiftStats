//
//  DeadCodeReport.swift
//  SwiftStatsCore
//
//  What the `periphery` collector found, mapped onto the scan (M7, design
//  §5.3, §5.4, §9.2): outskirts' version, each run's result count, every
//  entry of both runs with its class and where it is listed, the records
//  the unused production entries cover (each once per run, the lower
//  ordinal winning), the entries left out per class and run, and each
//  run's dead lines per module, summed over the maximal covered units.
//  Absent when the collector didn't run.
//

/// A snapshot's dead-code results, mapped to records.
public struct DeadCodeReport: Codable, Hashable, Sendable {
    /// outskirts' version, as `outskirts version` printed it.
    public let version: String
    /// Each run's result count, `roots` first.
    public let runs: [DeadCodeRunResults]
    /// Every entry of both runs, `roots` first, each run in outskirts'
    /// order.
    public let declarations: [DeadCodeDeclaration]
    /// The covered records, `roots` first, then by key.
    public let records: [DeadCodeRecord]
    /// The entries left out of the mapping, by class, per run (`DeadCodeRun`
    /// raw values).
    public let dropped: [String: DeadCodeDropped]
    /// Dead lines per module (target names) per run (`DeadCodeRun` raw
    /// values); a module with none is absent.
    public let deadLines: [String: [String: Int]]

    /// Creates a report. Fields are documented on their properties.
    public init(
        version: String,
        runs: [DeadCodeRunResults],
        declarations: [DeadCodeDeclaration],
        records: [DeadCodeRecord],
        dropped: [String: DeadCodeDropped],
        deadLines: [String: [String: Int]]
    ) {
        self.version = version
        self.runs = runs
        self.declarations = declarations
        self.records = records
        self.dropped = dropped
        self.deadLines = deadLines
    }

    /// The dead lines of `run` in `modules`.
    func deadLines(of run: DeadCodeRun, in modules: Set<String>) -> Int {
        deadLines[run.rawValue, default: [:]].filter { modules.contains($0.key) }.values.reduce(0, +)
    }
}
