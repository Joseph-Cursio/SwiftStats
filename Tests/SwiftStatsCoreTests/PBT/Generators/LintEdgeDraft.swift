//
//  LintEdgeDraft.swift
//  SwiftStatsCoreTests
//
//  P15.1's findings input: a `swiftlint lint --reporter json` report of
//  two violations and a SwiftProjectLint `--format json` report of one
//  issue at two places, whose every number (a violation's line and
//  column, the report's schema version, a place's line) is an integer
//  edge. Each violation, and the issue, lies in the scanned file without a
//  byte order mark or in a file the scan never read, named by its
//  absolute path as both tools name files.
//

import Foundation
import Testing

/// SwiftLint and SwiftProjectLint reports whose numbers are integer edges.
struct LintEdgeDraft: Sendable, CustomTestStringConvertible {
    /// One SwiftLint violation as drafted.
    struct Violation: Hashable, Sendable {
        /// Whether it lies in the scanned file.
        let scanned: Bool
        /// Its 1-based line.
        let line: Int
        /// Its 1-based column.
        let column: Int

        /// Its file, relative to the package root.
        var file: String {
            scanned ? IntegerEdgeGen.plainFile : IntegerEdgeGen.unscannedFile
        }
    }

    /// The violations, in the report's order.
    let violations: [Violation]
    /// The SwiftProjectLint report's schema version.
    let schemaVersion: Int
    /// Whether the issue lies in the scanned file.
    let issueScanned: Bool
    /// The lines of the issue's two places.
    let issueLines: [Int]

    /// The issue's file, relative to the package root.
    var issueFile: String {
        issueScanned ? IntegerEdgeGen.plainFile : IntegerEdgeGen.unscannedFile
    }

    /// The violations, the schema version and the issue.
    var testDescription: String {
        let shown = violations.map { "\($0.scanned ? "scanned" : "unscanned") \($0.line):\($0.column)" }
        return "violations [\(shown.joined(separator: ", "))]; schema \(schemaVersion), issue in "
            + "\(issueScanned ? "scanned" : "unscanned") at lines \(issueLines)"
    }

    /// The SwiftLint report, its files under `root`.
    func swiftLintReport(root: String) -> Data {
        let entries = violations.map { violation in
            """
            {"character": \(violation.column), "file": "\(root)/\(violation.file)", "line": \(violation.line), \
            "reason": "Force unwrapping should be avoided", "rule_id": "force_unwrapping", "severity": "Warning", \
            "type": "Force Unwrapping"}
            """
        }
        return Data(("[" + entries.joined(separator: ", ") + "]").utf8)
    }

    /// The SwiftProjectLint report, its files under `root`.
    func projectLintReport(root: String) -> Data {
        let locations = issueLines.map { line in
            "{\"filePath\": \"\(root)/\(issueFile)\", \"lineNumber\": \(line)}"
        }
        return Data(
            """
            {"schemaVersion": \(schemaVersion), "tool": {"name": "SwiftProjectLint", "version": "1.1.0"},
             "issues": [{"ruleIdentifier": "Force Try", "category": "safety", "kind": "defect", \
            "severity": "warning", "message": "Avoid try!", "symbol": "first()", \
            "locations": [\(locations.joined(separator: ", "))]}]}
            """.utf8
        )
    }
}
