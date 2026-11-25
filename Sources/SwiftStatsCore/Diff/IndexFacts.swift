//
//  IndexFacts.swift
//  SwiftStatsCore
//
//  What `diff` reads from the two snapshots' index results (M7, design
//  §3.6, §10.3): each side's primary USR by record key, only when the
//  `index` collector compares, so the `usr` match rule and the `usr
//  changed` facts never rest on results that don't compare. A key held by
//  several records keeps its first record's USR, as the store's rows do;
//  those records' families share the key, so the `usr` rule finds the USR
//  on several roots and matches none of them.
//

/// Each side's primary USRs, for the `usr` match rule and the `usr
/// changed` facts.
struct IndexFacts {
    /// No USRs: the index doesn't compare, or isn't read.
    static let empty = Self(old: [:], new: [:])

    /// The older snapshot's primary USRs, by record key.
    let old: [String: String]
    /// The newer snapshot's primary USRs, by record key.
    let new: [String: String]

    /// Facts holding `old` and `new`, each side's primary USRs by record
    /// key, as they are.
    init(old: [String: String], new: [String: String]) {
        self.old = old
        self.new = new
    }

    /// The primary USRs of `old` and `new`'s index results; none on either
    /// side unless the `index` collector is among `compared`.
    init(old: StoredIndex?, new: StoredIndex?, compared: Set<String>) {
        guard compared.contains(IndexAdapter.name), let old, let new else {
            self = .empty
            return
        }
        self.init(old: Self.primaries(of: old.report), new: Self.primaries(of: new.report))
    }

    /// `report`'s primary USRs by record key, the first record's for a key
    /// held by several.
    private static func primaries(of report: IndexReport) -> [String: String] {
        var usrs: [String: String] = [:]
        var seen: Set<String> = []
        for record in report.records where seen.insert(record.key).inserted {
            usrs[record.key] = record.usr
        }
        return usrs
    }

    /// The records of `pairs` (older, newer) whose key is the same on both
    /// sides and whose primary USR, held on both, differs: the key now
    /// names another declaration (a retargeted typealias, a type moved to
    /// another module). Sorted by key; never a delta.
    func changes(_ pairs: [(FunctionRow, FunctionRow)]) -> [USRChange] {
        pairs.compactMap { older, newer -> USRChange? in
            guard older.key == newer.key, let before = old[older.key], let after = new[newer.key],
                  before != after else {
                return nil
            }
            return USRChange(key: newer.key, before: before, after: after)
        }
        .sorted { ($0.key, $0.before) < ($1.key, $1.before) }
    }
}
