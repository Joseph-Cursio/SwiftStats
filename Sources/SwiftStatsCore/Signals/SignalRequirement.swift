//
//  SignalRequirement.swift
//  SwiftStatsCore
//
//  An input a signal needs before it is computed (PRD §6.5: a signal whose
//  inputs are missing is never computed from partial data). A signal
//  missing one is left out, with a reason saying which.
//

/// An input a signal needs.
enum SignalRequirement: Hashable, Sendable {
    /// A collector that ran on the snapshot, by name.
    case collector(String)
    /// The snapshot's history.
    case history
    /// A snapshot holding M4's rows: stored from a scan of schema 6 or
    /// later, with its scan facts.
    case m4Snapshot
    /// A snapshot holding M5's rows: stored from a scan of schema 7 or
    /// later, with a run of the coverage collector, whatever its state.
    case m5Snapshot

    /// The first scan schema whose snapshots hold M4's rows.
    static let firstM4Schema = 6
    /// The first scan schema whose snapshots hold M5's rows.
    static let firstM5Schema = 7
}
