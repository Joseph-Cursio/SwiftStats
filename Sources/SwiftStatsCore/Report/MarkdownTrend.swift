//
//  MarkdownTrend.swift
//  SwiftStatsCore
//
//  `swiftstats trend --format markdown`: one row per point, with breaks
//  marked where the numbers stop comparing.
//

/// Renders a trend as Markdown.
public enum MarkdownTrend {
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
        return lines.joined(separator: "\n") + "\n"
    }
}
