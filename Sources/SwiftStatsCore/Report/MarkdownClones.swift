//
//  MarkdownClones.swift
//  SwiftStatsCore
//
//  The report's Clones section (PRD §7.12): SwiftCloneDetector's merged
//  classes in the production files, counted by kind, never one line per
//  class, with the share of stripped lines a copy covers and the tool's
//  own duplicated-line counts as a hint. When the tool didn't run, the
//  section says why.
//

import Foundation

/// Renders the Clones section.
enum MarkdownClones {
    /// Percent in a whole.
    private static let percent = 100.0

    /// The section's lines after its heading.
    static func render(_ scan: ScanReport) -> [String] {
        guard let clones = scan.clones else {
            let status = scan.collectors.first { $0.name == SwiftCloneDetectorAdapter.name }
            let why = status.map { status in
                status.state.rawValue + (status.reason.map { ", \($0)" } ?? "")
            }
            return ["Not collected: \(why ?? "not in this snapshot")."]
        }
        let production = scan.rollups.first { $0.scope == .project && $0.name == "production" }
        guard let counts = production?.clones else {
            return ["No production code."]
        }
        let modules = Set(scan.targets.filter { $0.isTest == false }.map(\.name))
        let read = scan.files.filter { modules.contains($0.module) && $0.generated == false }
        let lines = read.map(\.strippedLines).reduce(0, +)
        let share = lines > 0
            ? String(format: "%.1f%%", Double(counts.clonedLines) * percent / Double(lines))
            : "—"
        let copies = clones.classes.map(\.instances.count).reduce(0, +)
        let tool = clones.toolDuplicatedLines
        let table = MarkdownTable(
            header: ["Kind", "Classes"],
            rows: [
                ["exact", String(counts.classes.exact)],
                ["renamed", String(counts.classes.renamed)],
                ["sequence", String(counts.classes.sequence)],
                ["near-miss", String(counts.classes.nearMiss)]
            ]
        )
        return [
            "SwiftCloneDetector's passes over the production files, generated ones left out, merged: "
                + "\(counted(clones.classes.count, "class", "classes")) of \(counted(copies, "copy", "copies")). "
                + "Copies cover \(counts.clonedLines) of \(lines) stripped lines (\(share))."
        ] + [""] + table.lines(empty: "") + [
            "",
            "The tool's own duplicated lines, a hint only (each class's first copy, once per further copy, "
                + "nested classes counted again): subtree \(tool.subtree), type1 \(tool.type1), "
                + "sequence \(tool.sequence), near-miss \(tool.nearMiss)."
        ]
    }

    /// `count` with the noun in the singular for one.
    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
