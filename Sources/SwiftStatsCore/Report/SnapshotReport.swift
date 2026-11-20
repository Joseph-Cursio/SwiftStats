//
//  SnapshotReport.swift
//  SwiftStatsCore
//
//  `swiftstats report --format json` (PRD §10): a snapshot's metadata, its
//  derived signals and its scan report. It has its own `schemaVersion`; the
//  scan report inside keeps its own.
//

/// A stored snapshot, as `report` writes it.
public struct SnapshotReport: Codable, Hashable, Sendable {
    /// The version of this document's format: 2 adds the signals (M3); 3
    /// names each item's `subject` (it was `family`) and moves its inputs
    /// into payloads, M3's into `history` (M4).
    public static let currentSchemaVersion = 3

    /// The document's format version.
    public let schemaVersion: Int
    /// Which state of which package, when, and each collector's run.
    public let snapshot: SnapshotInfo
    /// The derived signals, in report order, each with its members only.
    public let signals: [SignalResult]
    /// The measurements.
    public let scan: ScanReport

    /// The report of `snapshot`, its `signals` and its `scan`. Each signal
    /// keeps only its members.
    public init(snapshot: SnapshotInfo, signals: [SignalResult], scan: ScanReport) {
        schemaVersion = Self.currentSchemaVersion
        self.snapshot = snapshot
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
