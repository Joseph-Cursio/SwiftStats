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
    /// The fraction Swift writes on a whole `Double`.
    private static let wholeFraction = ".0"

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

    /// `value` in full, for a threshold a report states: the shortest
    /// decimal that reads back as `value`, with no exponent, no `.0` on a
    /// whole number and no sign on zero, so the number printed is the one
    /// compared.
    static func exact(_ value: Double) -> String {
        let text = "\(value == 0 ? 0 : value)"
        guard let marker = text.firstIndex(where: { $0 == "e" || $0 == "E" }),
              let exponent = Int(text[text.index(after: marker)...]) else {
            return text.hasSuffix(wholeFraction) ? String(text.dropLast(wholeFraction.count)) : text
        }
        var mantissa = text[..<marker]
        let sign = mantissa.hasPrefix("-") ? "-" : ""
        mantissa = mantissa.drop { $0 == "-" }
        let digits = mantissa.filter { $0 != "." }
        let point = (mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.startIndex, to: $0) }
            ?? mantissa.count) + exponent
        if point <= 0 {
            return sign + "0." + String(repeating: "0", count: -point) + digits
        }
        if point >= digits.count {
            return sign + digits + String(repeating: "0", count: point - digits.count)
        }
        return sign + digits.prefix(point) + "." + digits.dropFirst(point)
    }

    /// An optional count, or a dash.
    static func optional(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }
}
