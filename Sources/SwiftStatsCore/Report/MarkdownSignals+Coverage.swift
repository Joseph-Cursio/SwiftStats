//
//  MarkdownSignals+Coverage.swift
//  SwiftStatsCore
//
//  The input columns of M5's signal tables (PRD §8): the markers and
//  coverage of a risky + untested item, and the copies of an uneven clone
//  testing item with their line coverage. A cell whose payload is absent
//  shows a dash.
//

extension MarkdownSignals {
    /// Risky + untested: the markers no test ran, by rule, and the
    /// subject's coverage.
    static var riskyUntestedColumns: [Column] {
        [
            ("Untested by rule", markers(untestedByRule)),
            ("On partly run lines", markers { String($0.onPartlyRunLines) }),
            ("Lines", coverage { tally($0.lines) }),
            ("Regions", coverage { tally($0.regions) })
        ]
    }

    /// Uneven clone testing: each copy's line coverage, and the class.
    static var unevenCloneTestingColumns: [Column] {
        [
            ("Copies covered", cloneCoverage { $0.copies.map(coveredCopy).joined(separator: "; ") }),
            ("Kind", clone(kind)),
            ("Folded", cloneCoverage { $0.folded.isEmpty ? "—" : $0.folded.map { "#\($0)" }.joined(separator: ", ") })
        ]
    }

    /// Each rule's untested markers of its markers, by rule name.
    private static func untestedByRule(_ markers: SignalItem.Markers) -> String {
        markers.byRule.sorted { $0.key < $1.key }
            .map { rule, counts in "\(rule) \(counts.first ?? 0)/\(counts.last ?? 0)" }
            .joined(separator: ", ")
    }

    /// Covered of total, with the percentage; a dash without data.
    static func tally(_ tally: CoverageTally?) -> String {
        guard let tally else {
            return "—"
        }
        let percent = CoverageRollup.Share.percent(covered: tally.covered, total: tally.total)
        return "\(tally.covered)/\(tally.total)" + (percent.map { " (\(MarkdownNumber.value($0))%)" } ?? "")
    }

    /// A copy: its family and its covered of mapped lines.
    private static func coveredCopy(_ copy: SignalItem.CoveredCopy) -> String {
        "\(display(copy.family, file: copy.file, line: copy.line)): \(copy.covered)/\(copy.mapped)"
    }

    /// A cell reading an item's markers with `cell`.
    private static func markers(_ cell: @escaping (SignalItem.Markers) -> String) -> (SignalItem) -> String {
        { item in item.markers.map(cell) ?? "—" }
    }

    /// A cell reading an item's coverage with `cell`.
    static func coverage(_ cell: @escaping (SignalItem.Coverage) -> String) -> (SignalItem) -> String {
        { item in item.coverage.map(cell) ?? "—" }
    }

    /// A cell reading an item's clone coverage with `cell`.
    private static func cloneCoverage(
        _ cell: @escaping (SignalItem.CloneCoverage) -> String
    ) -> (SignalItem) -> String {
        { item in item.clone?.coverage.map(cell) ?? "—" }
    }
}
