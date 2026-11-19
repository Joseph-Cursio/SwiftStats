//
//  MarkdownTable.swift
//  SwiftStatsCore
//
//  A GitHub-flavoured Markdown table, for reports and diffs.
//

/// Builds a Markdown table.
struct MarkdownTable {
    /// The header row.
    let header: [String]
    /// The body rows.
    var rows: [[String]] = []

    /// `cell` with pipes escaped and line breaks as `<br>`, so it stays
    /// in one column of one row.
    private static func escape(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
    }

    /// The table's lines, or a single line saying `empty` when there are no rows.
    func lines(empty: String) -> [String] {
        guard rows.isEmpty == false else {
            return [empty]
        }
        let separator = header.map { _ in "---" }
        return ([header, separator] + rows).map { cells in
            "| " + cells.map(Self.escape).joined(separator: " | ") + " |"
        }
    }
}
