//
//  MarkdownDiff.swift
//  SwiftStatsCore
//
//  `swiftstats diff --format markdown` (PRD §6.6, §10): a summary, the
//  function families that changed, metric deltas grouped into worse, better
//  and neutral, and what couldn't be compared.
//

/// Renders a diff as Markdown.
public enum MarkdownDiff {
    /// How many characters of a commit to show.
    private static let shortCommitLength = 10

    /// `diff` as Markdown, ending in a newline.
    public static func render(_ diff: SnapshotDiffReport) -> String {
        var lines = ["# \(diff.newer.package): \(side(diff.older)) → \(side(diff.newer))", ""]
        guard diff.isEmpty == false else {
            lines += ["No changes."] + notCompared(diff) + warnings(diff)
            return lines.joined(separator: "\n") + "\n"
        }
        let own = diff.collectors.first { $0.name == SwiftStatsCollector.name }
        if let own, own.outcome != .compared {
            let reason = own.reason.map { ": \($0)" } ?? ""
            lines += ["Functions and roll-ups: not compared, since SwiftStats' own results don't compare\(reason)."]
        } else {
            lines += summary(diff)
            lines += ["", "## Functions", ""] + families(diff.families)
        }
        let deltas = diff.functions.flatMap { function in
            function.metrics.map { (place: function.key, delta: $0) }
        } + diff.rollups.map { (place: "\($0.scope.rawValue) \($0.name)", delta: $0.delta) }
        for verdict in [DeltaVerdict.worse, .better, .neutral] {
            let rows = deltas.filter { $0.delta.verdict == verdict }
            guard rows.isEmpty == false else {
                continue
            }
            var table = MarkdownTable(header: ["Where", "Metric", "Before", "After"])
            table.rows = rows.map { [$0.place, $0.delta.metric, number($0.delta.before), number($0.delta.after)] }
            lines += ["", "## \(verdict.rawValue.capitalized)", ""] + table.lines(empty: "")
        }
        lines += notCompared(diff) + warnings(diff)
        return lines.joined(separator: "\n") + "\n"
    }

    /// A snapshot's short name.
    private static func side(_ side: DiffSide) -> String {
        let commit = side.commit.map { String($0.prefix(shortCommitLength)) } ?? "no commit"
        return side.isDirty ? "\(commit) (uncommitted)" : commit
    }

    /// Counts of each family status.
    private static func summary(_ diff: SnapshotDiffReport) -> [String] {
        let statuses = diff.families.flatMap(\.statuses)
        let counts = Dictionary(grouping: statuses, by: \.self).mapValues(\.count)
        let parts = counts.keys.sorted().map { "\(counts[$0] ?? 0) \($0.rawValue)" }
        return ["Functions: " + (parts.isEmpty ? "no changes" : parts.joined(separator: ", ")) + "."]
    }

    /// One row per changed family.
    private static func families(_ families: [FamilyChange]) -> [String] {
        var table = MarkdownTable(header: ["Function", "Change", "File", "Matched by"])
        table.rows = families.map { family in
            let file: String
            if let old = family.oldFile, let new = family.newFile, old != new {
                file = "\(old) → \(new)"
            } else {
                file = family.newFile ?? family.oldFile ?? ""
            }
            let renamed = family.oldKey.map { $0 == family.key ? "" : " (was \($0))" } ?? ""
            return [
                family.key + renamed,
                family.statuses.map(\.rawValue).joined(separator: ", "),
                file,
                family.matchedBy?.rawValue ?? ""
            ]
        }
        return table.lines(empty: "No function changes.")
    }

    /// The collectors that weren't compared, and why.
    private static func notCompared(_ diff: SnapshotDiffReport) -> [String] {
        let skipped = diff.collectors.filter { $0.outcome != .compared }
        guard skipped.isEmpty == false else {
            return []
        }
        var table = MarkdownTable(header: ["Collector", "Outcome", "Why"])
        table.rows = skipped.map { [$0.name, $0.outcome.rawValue, $0.reason ?? ""] }
        return ["", "## Not compared", ""] + table.lines(empty: "")
    }

    /// The diff's warnings.
    private static func warnings(_ diff: SnapshotDiffReport) -> [String] {
        guard diff.warnings.isEmpty == false else {
            return []
        }
        return ["", "## Warnings", ""] + diff.warnings.map { "- \($0)" }
    }

    /// A value, or a dash when missing.
    private static func number(_ value: Double?) -> String {
        value.map(MarkdownNumber.value) ?? "—"
    }
}
