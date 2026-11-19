//
//  ScanReportEncoder.swift
//  SwiftStatsCore
//
//  Deterministic JSON for SwiftStats' documents (PRD §9): sorted keys,
//  two-space indentation from the pretty printer, unescaped slashes, and a
//  final newline.
//

import Foundation

/// Encodes scan reports, snapshot reports and diffs as stable JSON.
public enum ScanReportEncoder {
    /// The document as UTF-8 JSON ending in a newline.
    public static func encode(_ report: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(report)
        data.append(contentsOf: Array("\n".utf8))
        return data
    }
}
