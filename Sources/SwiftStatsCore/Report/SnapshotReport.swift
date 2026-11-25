//
//  SnapshotReport.swift
//  SwiftStatsCore
//
//  `swiftstats report --format json` (PRD §10): a snapshot's metadata, its
//  derived signals with the thresholds they used, and its scan report. It
//  has its own `schemaVersion`; the scan report inside keeps its own.
//

/// A stored snapshot, as `report` writes it.
public struct SnapshotReport: Codable, Hashable, Sendable {
    /// The version of this document's format: 2 adds the signals (M3); 3
    /// names each item's `subject` (it was `family`) and moves its inputs
    /// into payloads, M3's into `history` (M4); 4 adds the coverage
    /// signals and their payloads, `markers`, `coverage` and a clone
    /// class's `coverage` (M5); 5 adds the mutation signals and their
    /// payloads, `mutation`, `ratio`, `propertyTarget` and a clone class's
    /// `mutation`, and `thresholds`, those the signals used (M6); 6 adds
    /// the index signals (hidden coupling, dead but tested, test-only
    /// production code) and their payloads, `coupling`, `dead` and
    /// `references`, a dead-but-tested item's `mutation.coverage`, and the
    /// hidden-coupling limits under `thresholds` (M7).
    public static let currentSchemaVersion = 6

    /// The document's format version.
    public let schemaVersion: Int
    /// Which state of which package, when, and each collector's run.
    public let snapshot: SnapshotInfo
    /// The derived signals, in report order, each with its members only.
    public let signals: [SignalResult]
    /// The thresholds the signals used.
    public let thresholds: ReportThresholds
    /// The measurements.
    public let scan: ScanReport

    /// The report of `snapshot`, its `signals` computed with `thresholds`,
    /// and its `scan`. Each signal keeps only its members.
    public init(snapshot: SnapshotInfo, signals: [SignalResult], thresholds: SignalThresholds, scan: ScanReport) {
        schemaVersion = Self.currentSchemaVersion
        self.snapshot = snapshot
        self.thresholds = ReportThresholds(thresholds)
        self.signals = signals.map { signal in
            SignalResult(
                name: signal.name,
                leftOut: signal.leftOut,
                rule: signal.rule,
                candidates: signal.candidates,
                items: signal.members
            )
        }
        self.scan = scan
    }
}
