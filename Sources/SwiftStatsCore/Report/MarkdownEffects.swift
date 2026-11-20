//
//  MarkdownEffects.swift
//  SwiftStatsCore
//
//  The report's Side effects section (PRD §7.10): production records by
//  resolved tier and by purity verdict, counts only, never one line per
//  record. When SwiftEffectInference didn't run, the section says why.
//

/// Renders the Side effects section.
enum MarkdownEffects {
    /// How many characters of the revision to show.
    private static let shortRevisionLength = 10

    /// The section's lines after its heading: the production part's counts,
    /// or why there are none.
    static func render(_ scan: ScanReport) -> [String] {
        guard let summary = scan.effects else {
            let status = scan.collectors.first { $0.name == EffectCollector.name }
            let why = status.map { status in
                status.state.rawValue + (status.reason.map { ", \($0)" } ?? "")
            }
            return ["Not collected: \(why ?? "not in this snapshot")."]
        }
        let production = scan.rollups.first { $0.scope == .project && $0.name == "production" }
        guard let effects = production?.effects else {
            return ["No production code."]
        }
        let revision = String(summary.revision.prefix(shortRevisionLength))
        let passes = summary.passes == 1 ? "1 pass" : "\(summary.passes) passes"
        var lines = [
            "Production functions, getters and subscripts. SwiftEffectInference \(revision); "
                + "body inference settled in \(passes)."
        ]
        lines += [""] + counts("Tier", EffectFacts.Tier.allCases.map(\.rawValue), effects.tier)
        lines += [""] + counts("Purity", EffectFacts.Purity.allCases.map(\.rawValue), effects.purity)
        return lines
    }

    /// One row per value of `values`, in that order, with its count.
    private static func counts(_ label: String, _ values: [String], _ counts: [String: Int]) -> [String] {
        let table = MarkdownTable(
            header: [label, "Records"],
            rows: values.map { value in [value, String(counts[value, default: 0])] }
        )
        return table.lines(empty: "")
    }
}
