//
//  MarkdownTrend.swift
//  SwiftStatsCore
//
//  `swiftstats trend --format markdown`: one row per point, with breaks
//  marked where the numbers stop comparing, and for a type-check time
//  (`typecheck.*`, M7) a footnote that it depends on the machine and its
//  load, which no build identity names (design §10.4).
//

/// Renders a trend as Markdown.
public enum MarkdownTrend {
    /// What the metrics of type-check times start with.
    static let typeCheckPrefix = "typecheck."
    /// The footnote under a type-check time's trend.
    static let typeCheckNote = "Type-check times depend on the machine and its load, which no build identity names, "
        + "and two builds' figures differ by a fifth to a third per function: read large moves only."

    /// `report` as Markdown, ending in a newline.
    public static func render(_ report: TrendReport) -> String {
        let place = report.scope == .project ? "the project's \(report.name) code" : "module \(report.name)"
        var lines = ["# \(report.package): \(report.metric)", "", "For \(place), over HEAD's first-parent commits."]
        lines.append("")
        var table = MarkdownTable(header: ["Commit", "Date", "Value", "Break"])
        for point in report.points {
            table.rows.append([
                String(point.commit.prefix(MarkdownSignals.shortLength)),
                String(point.date.prefix(MarkdownSignals.shortLength)),
                point.value.map(MarkdownNumber.value) ?? "—",
                point.breakReason ?? ""
            ])
        }
        lines += table.lines(empty: "No snapshots on HEAD's first-parent line; run `swiftstats backfill`.")
        if report.offLine > 0 {
            lines += ["", "\(report.offLine) snapshots of commits off the first-parent line are not shown."]
        }
        if report.metric.hasPrefix(typeCheckPrefix) {
            lines += ["", typeCheckNote]
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
