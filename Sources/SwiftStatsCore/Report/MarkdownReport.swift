//
//  MarkdownReport.swift
//  SwiftStatsCore
//
//  `swiftstats report --format markdown` (PRD §10): derived signals first,
//  then the collectors, the project roll-up with findings per 1k stripped
//  lines (D6), the side-effect counts, the history's notes, and per-module
//  detail.
//

/// Renders a snapshot report as Markdown.
public enum MarkdownReport {
    /// The project parts, in report order.
    private static let projectParts = ["production", "tests"]
    /// How many characters of a commit to show.
    private static let shortCommitLength = 10

    /// `report` as Markdown, ending in a newline.
    public static func render(_ report: SnapshotReport) -> String {
        var lines = header(report.snapshot)
        lines += ["", "## Signals"] + MarkdownSignals.render(report.signals, history: report.scan.history)
        lines += ["", "## Collectors", ""] + collectors(report.snapshot.collectors)
        let project = projectParts.compactMap { part in
            report.scan.rollups.first { $0.scope == .project && $0.name == part }
        }
        lines += ["", "## Project", ""] + summary(project)
        lines += ["", "### Findings by rule", ""] + findings(project, field: \.findings, label: "Rule")
        lines += ["", "### Findings by kind", ""] + findings(project, field: \.findingKinds, label: "Kind")
        lines += ["", "## Side effects", ""] + MarkdownEffects.render(report.scan)
        if let history = report.scan.history {
            lines += ["", "## History", ""] + MarkdownSignals.history(history)
        }
        let modules = report.scan.rollups.filter { $0.scope == .module }.sorted { $0.name < $1.name }
        lines += ["", "## Modules", ""] + summary(modules)
        return lines.joined(separator: "\n") + "\n"
    }

    /// The title and the snapshot's provenance.
    private static func header(_ snapshot: SnapshotInfo) -> [String] {
        let commit = snapshot.git.commit.map { String($0.prefix(shortCommitLength)) } ?? "no commit"
        let state = snapshot.git.isDirty ? ", with uncommitted changes" : ""
        let branch = snapshot.git.branch.map { " on \($0)" } ?? ""
        var lines = ["# \(snapshot.package)", "", "Snapshot of \(commit)\(branch)\(state), taken \(snapshot.date)."]
        if let swift = snapshot.toolchain.swiftVersion {
            lines += ["", "Toolchain: \(swift)."]
        }
        return lines
    }

    /// One row per collector run.
    private static func collectors(_ runs: [CollectorRunInfo]) -> [String] {
        var table = MarkdownTable(header: ["Collector", "Status", "Version", "Time", "Note"])
        for run in runs {
            table.rows.append([
                run.name,
                run.state.rawValue,
                run.version ?? "—",
                MarkdownNumber.seconds(run.durationMilliseconds),
                run.reason ?? ""
            ])
        }
        return table.lines(empty: "No collectors ran.")
    }

    /// One row per roll-up: its size, complexity and findings.
    private static func summary(_ rollups: [Rollup]) -> [String] {
        var table = MarkdownTable(header: [
            "", "Files", "Functions", "Function lines", "Median cognitive", "p90 cognitive",
            "Public (documented)", "Tests", "Findings per 1k lines"
        ])
        for rollup in rollups {
            let findings = rollup.findings.values.reduce(0) { $0 + $1.values.reduce(0, +) }
            let tests = rollup.tests.tests.values.reduce(0) { $0 + $1.values.reduce(0, +) }
            table.rows.append([
                rollup.name,
                String(rollup.files),
                String(rollup.functions.values.reduce(0, +)),
                String(rollup.functionLength.total),
                MarkdownNumber.optional(rollup.cognitive.median),
                MarkdownNumber.optional(rollup.cognitive.p90),
                "\(rollup.api.publicDeclarations) (\(rollup.api.documentedPublicDeclarations))",
                String(tests),
                MarkdownNumber.perThousand(findings, lines: rollup.fileLength.total)
            ])
        }
        return table.lines(empty: "Nothing scanned.")
    }

    /// Findings by tool and `field`'s inner key, per project part, with
    /// counts per 1k stripped lines of that part.
    private static func findings(
        _ parts: [Rollup],
        field: KeyPath<Rollup, [String: [String: Int]]>,
        label: String
    ) -> [String] {
        var table = MarkdownTable(header: ["Part", "Tool", label, "Count", "Per 1k lines"])
        for part in parts {
            let counts = part[keyPath: field].flatMap { tool, byName in
                byName.map { (tool: tool, name: $0.key, count: $0.value) }
            }
            let ordered = counts.sorted { lhs, rhs in
                (rhs.count, lhs.tool, lhs.name) < (lhs.count, rhs.tool, rhs.name)
            }
            for entry in ordered {
                table.rows.append([
                    part.name,
                    entry.tool,
                    entry.name,
                    String(entry.count),
                    MarkdownNumber.perThousand(entry.count, lines: part.fileLength.total)
                ])
            }
        }
        return table.lines(empty: "No findings.")
    }
}
