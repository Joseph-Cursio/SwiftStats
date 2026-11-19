//
//  MarkdownNumber.swift
//  SwiftStatsCore
//
//  Number formats for Markdown output, fixed so output is deterministic.
//

import Foundation

/// Formats numbers for reports.
enum MarkdownNumber {
    /// Lines per normalised unit (PRD D6).
    static let linesPerUnit = 1_000.0
    /// Milliseconds in a second.
    private static let millisecondsPerSecond = 1_000.0

    /// `count` per 1k of `lines`, to one decimal place; a dash for no lines.
    static func perThousand(_ count: Int, lines: Int) -> String {
        guard lines > 0 else {
            return "—"
        }
        return String(format: "%.1f", Double(count) * linesPerUnit / Double(lines))
    }

    /// `milliseconds` in seconds, to one decimal place.
    static func seconds(_ milliseconds: Int) -> String {
        String(format: "%.1f s", Double(milliseconds) / millisecondsPerSecond)
    }

    /// `value` without a fraction when it is whole, else to two places.
    static func value(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// An optional count, or a dash.
    static func optional(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }
}
