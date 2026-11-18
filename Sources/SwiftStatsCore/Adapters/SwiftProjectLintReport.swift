//
//  SwiftProjectLintReport.swift
//  SwiftStatsCore
//
//  The parts of SwiftProjectLint's JSON report (schema 1, from 1.1.0) the
//  adapter reads (PRD §7.15).
//

/// SwiftProjectLint's `--format json` output.
struct SwiftProjectLintReport: Decodable {
    /// The report's tool block.
    struct Tool: Decodable {
        let name: String
        let version: String
    }

    /// One issue.
    struct Issue: Decodable {
        let ruleIdentifier: String
        let category: String
        let kind: FindingKind
        let severity: String
        let message: String
        let symbol: String?
        let locations: [Location]
    }

    /// A place an issue names, relative to the project root.
    struct Location: Decodable {
        let filePath: String
        let lineNumber: Int
    }

    /// Only the schema version is read first, so an unknown version is
    /// reported as such rather than as a decoding error.
    struct Header: Decodable {
        let schemaVersion: Int?
    }

    let schemaVersion: Int
    let tool: Tool
    let issues: [Issue]
}
