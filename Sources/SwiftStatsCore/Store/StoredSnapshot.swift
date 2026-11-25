//
//  StoredSnapshot.swift
//  SwiftStatsCore
//
//  A snapshot read back from the store's tables, as `diff` and the
//  signals use it. A snapshot stored before v3 has no scan facts, empty
//  M4 lists, and function rows without their v3 columns; one stored before
//  v4 has no coverage and function rows without access or owning type;
//  one stored before v5 has no mutation results; one stored before v6 has
//  no T1 results and no coupling pairs. The executable targets, which only
//  the stored scan report names, are read for a snapshot holding index
//  results alone.
//

/// A snapshot's metadata and its rows.
public struct StoredSnapshot: Hashable, Sendable {
    /// The row id.
    public let id: Int64
    /// The metadata and collector runs.
    public let info: SnapshotInfo
    /// The `schemaVersion` of the scan report it was stored from.
    public let reportSchemaVersion: Int
    /// Its function records.
    public let functions: [FunctionRow]
    /// Its finding locations.
    public let findings: [FindingRow]
    /// Its roll-up numbers.
    public let rollups: [RollupMetricRow]
    /// Its history run; nil when history wasn't read.
    public let history: HistoryRunRow?
    /// Its families' history.
    public let familyHistory: [FamilyHistoryRow]
    /// Its scan-wide facts; nil for a snapshot stored before v3.
    public let scanFacts: ScanFactsRow?
    /// SwiftInferProperties' candidates, in the report's order.
    public let candidates: [PropertyCandidate]
    /// The law-check pairs, in the report's order.
    public let lawChecks: [LawCheck]
    /// The clone classes with their copies, by ordinal.
    public let cloneClasses: [CloneClass]
    /// History's commit log, newest first: `familyChanges` name commits by
    /// their positions in it.
    public let historyCommits: [HistoryLogEntry]
    /// Each commit that changed each family, by family, file, then position.
    public let familyChanges: [FamilyChangeRow]
    /// History's change-coupling pairs, in the history block's order;
    /// empty when history wasn't read, and for a snapshot stored before v6.
    public let couplingPairs: [CouplingPair]
    /// Its coverage, as the scan JSON holds it, and when it was collected;
    /// nil when it holds none.
    public let coverage: StoredCoverage?
    /// Its mutation results, as the scan JSON holds them; nil when it
    /// holds none.
    public let mutation: StoredMutation?
    /// Its index results, as the scan JSON holds them, and when they were
    /// collected; nil when it holds none.
    public let index: StoredIndex?
    /// Its T1 build results, as the scan JSON holds them, and when they
    /// were collected; nil when it holds none.
    public let build: StoredBuild?
    /// Its dead-code results, as the scan JSON holds them, and when they
    /// were collected; nil when it holds none.
    public let deadCode: StoredDeadCode?
    /// Its executable targets, by name, from its stored report: where a
    /// parameterless `static func main()` is an entry point (test-only
    /// production code, M7 design §8.3). Read only for a snapshot holding
    /// index results; empty for any other.
    public let executableTargets: Set<String>
}
