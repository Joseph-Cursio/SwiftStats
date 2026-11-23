//
//  StoreError.swift
//  SwiftStatsCore
//
//  Why the snapshot store couldn't do what was asked (PRD §9), or wouldn't:
//  a scan may not replace coverage (M5) or mutation results (M6) it can't
//  carry, or can't read, and `scan --mutation --since` needs a stored
//  snapshot whose mutation results it can merge with (M6).
//

/// A snapshot store failure.
public enum StoreError: Error, CustomStringConvertible, Equatable {
    /// A stored report didn't decompress to its recorded length.
    case corruptReport(String)
    /// The snapshot a scan would replace holds coverage, collected at
    /// `collectedAt`, that the scan didn't collect and can't carry, for
    /// `reason` (M5); `snapshot` names the snapshot.
    case coverageNotKept(snapshot: String, collectedAt: String, reason: String)
    /// The snapshot a scan would replace holds coverage too damaged to
    /// read, for `reason`, that the scan didn't collect (M5); `snapshot`
    /// names the snapshot.
    case damagedCoverage(snapshot: String, reason: String)
    /// The snapshot a scan would replace holds mutation results too
    /// damaged to read, for `reason`, that the scan didn't collect (M6,
    /// design §6.4); `snapshot` names the snapshot.
    case damagedMutation(snapshot: String, reason: String)
    /// The snapshot a scan would replace holds mutation results, collected
    /// at `collectedAt`, that the scan didn't collect and can't carry, for
    /// `reason` (M6, design §6.4); `snapshot` names the snapshot.
    case mutationNotKept(snapshot: String, collectedAt: String, reason: String)
    /// The store holds migrations this build doesn't know.
    case newerStore(String)
    /// `scan --mutation --since` found no stored mutation results it can
    /// merge with, for the reason given (M6, design §6.1).
    case noMutationBase(String)
    /// No snapshot matched.
    case noSnapshot(String)
    /// A stored report was written with another report schema.
    case reportSchema(stored: Int, current: Int)
    /// The working tree has changes no stored snapshot covers.
    case workingTreeChanged(String)

    /// The message the command line shows.
    public var description: String {
        switch self {
        case .newerStore(let path):
            "the store at \(path) was written by a newer SwiftStats; use that version or another --store"

        case let .reportSchema(stored, current):
            "this snapshot's report was written with schema \(stored) and this SwiftStats reads \(current); "
                + "rescan the commit to rebuild it"

        case .corruptReport(let reason):
            "a stored report is damaged: \(reason)"

        case let .coverageNotKept(snapshot, collectedAt, reason):
            "the snapshot of \(snapshot) holds coverage from \(collectedAt) that this scan can't keep (\(reason)); "
                + "run scan --coverage to collect it again, or --drop-coverage to replace it"

        case let .damagedCoverage(snapshot, reason):
            "the snapshot of \(snapshot) holds coverage too damaged to read (\(reason)); "
                + "run scan --coverage to collect it again, or --drop-coverage to replace it without its coverage"

        case let .mutationNotKept(snapshot, collectedAt, reason):
            "the snapshot of \(snapshot) holds mutation results from \(collectedAt) that this scan can't keep "
                + "(\(reason)); run scan --mutation to collect them again, or --drop-mutation to replace them"

        case let .damagedMutation(snapshot, reason):
            "the snapshot of \(snapshot) holds mutation results too damaged to read (\(reason)); "
                + "run scan --mutation to collect them again, or --drop-mutation to replace it without them"

        case .noMutationBase(let reason):
            "scan --mutation --since: \(reason)"

        case .noSnapshot(let what):
            "no snapshot of \(what); run `swiftstats scan` first"

        case .workingTreeChanged(let package):
            "\(package)'s working tree has changed since its last scan; run `swiftstats scan`, "
                + "or pass --commit HEAD for HEAD's clean snapshot"
        }
    }
}
