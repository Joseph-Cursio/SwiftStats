//
//  StoreError.swift
//  SwiftStatsCore
//
//  Why the snapshot store couldn't do what was asked (PRD §9).
//

/// A snapshot store failure.
public enum StoreError: Error, CustomStringConvertible, Equatable {
    /// A stored report didn't decompress to its recorded length.
    case corruptReport(String)
    /// The store holds migrations this build doesn't know.
    case newerStore(String)
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

        case .noSnapshot(let what):
            "no snapshot of \(what); run `swiftstats scan` first"

        case .workingTreeChanged(let package):
            "\(package)'s working tree has changed since its last scan; run `swiftstats scan`, "
                + "or pass --commit HEAD for HEAD's clean snapshot"
        }
    }
}
