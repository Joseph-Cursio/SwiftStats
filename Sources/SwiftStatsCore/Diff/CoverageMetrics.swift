//
//  CoverageMetrics.swift
//  SwiftStatsCore
//
//  Each record's coverage on each side of a diff (M5, PRD §6.6), when the
//  coverage collector's results compare: its line and region percentages,
//  named as the roll-ups' are. A record with no coverage data, or none to
//  count, has no value, never 0.
//

/// Coverage percentages of records by key.
struct CoverageMetrics {
    /// The metric of a record's line percentage.
    static let lines = "coverage.lines.percent"
    /// The metric of a record's region percentage.
    static let regions = "coverage.regions.percent"

    /// Values in the older snapshot: record key → metric → value.
    let old: [String: [String: Double]]
    /// Values in the newer snapshot.
    let new: [String: [String: Double]]

    /// The values of `old` and `new`; empty unless `compared` holds the
    /// coverage collector.
    init(old: StoredCoverage?, new: StoredCoverage?, compared: Set<String>) {
        let compares = compared.contains(CoverageAdapter.name)
        self.old = compares ? Self.values(of: old) : [:]
        self.new = compares ? Self.values(of: new) : [:]
    }

    /// Each record's percentages in `coverage`, by key.
    private static func values(of coverage: StoredCoverage?) -> [String: [String: Double]] {
        let pairs = (coverage?.report.records ?? []).map { record in
            (record.key, values(of: record))
        }
        return Dictionary(pairs.filter { $0.1.isEmpty == false }) { first, _ in first }
    }

    /// `record`'s percentages that have a value.
    private static func values(of record: CoverageRecord) -> [String: Double] {
        let percent = { (tally: CoverageTally?) in
            tally.flatMap { CoverageRollup.Share.percent(covered: $0.covered, total: $0.total) }
        }
        let optional: [String: Double?] = [lines: percent(record.lines), regions: percent(record.regions)]
        return optional.compactMapValues(\.self)
    }
}
