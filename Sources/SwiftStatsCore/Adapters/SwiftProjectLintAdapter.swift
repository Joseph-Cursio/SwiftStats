//
//  SwiftProjectLintAdapter.swift
//  SwiftStatsCore
//
//  Runs SwiftProjectLint and reads its JSON (PRD §7.15). Two runs, each with
//  a config of SwiftStats' own so the package's `.swiftprojectlint.yml`
//  changes nothing: every default rule, then the opt-in rules SwiftStats
//  reads, which `enabled_only` turns on.
//

import Foundation

/// The SwiftProjectLint adapter.
enum SwiftProjectLintAdapter {
    /// The collector's name.
    static let name = "swiftprojectlint"
    /// The JSON schema this adapter reads.
    static let schemaVersion = 1
    /// SwiftProjectLint's exit status when it found warnings.
    private static let foundWarnings: Int32 = 1
    /// SwiftProjectLint's exit status when it found errors.
    private static let foundErrors: Int32 = 2
    /// Exit statuses that mean the run worked: clean, warnings, errors.
    private static let acceptedStatuses: Set<Int32> = [0, foundWarnings, foundErrors]
    /// Display names of the opt-in rules SwiftStats reads (§7.15).
    static let optInRules = [
        "Duplicate Enum Mapping", "Duplicate Struct Shape", "Parallel Enum Shape", "Scattered Enum Mapping",
        "Test Missing Assertion", "Test Missing Expect", "Test Missing Require", "Unused Protocol Requirement"
    ]
    /// The two configs, in run order.
    static let configs = [
        "disabled_rules: []\n",
        "enabled_only:\n" + optInRules.map { "  - \"\($0)\"\n" }.joined()
    ]
    /// How the two runs are recorded in the collector's status.
    static let options = [
        "--format json, config: disabled_rules: []",
        "--format json, config: enabled_only: " + optInRules.joined(separator: ", ")
    ]

    /// Runs `executable` on the package at `root`.
    static func run(executable: URL, root: URL) -> AdapterResult {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftStats-\(UUID().uuidString)")
            ScratchRegistry.shared.track(directory)
            defer { ScratchRegistry.shared.remove(directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var findings: [RawFinding] = []
            var warnings: [ScanWarning] = []
            var version = ""
            for (index, config) in configs.enumerated() {
                let file = directory.appendingPathComponent("swiftprojectlint-\(index).yml")
                try config.write(to: file, atomically: true, encoding: .utf8)
                let output = try ProcessRunner.run(
                    executable: executable.path,
                    arguments: [root.path, "--format", "json", "--config", file.path],
                    in: root,
                    accepting: acceptedStatuses
                )
                let report = try decode(output.output)
                version = report.tool.version
                findings += report.issues.map { finding(for: $0, root: root) }
                warnings += ruleNameWarnings(in: output.errorText)
            }
            return AdapterResult(
                status: CollectorStatus(name: name, state: .ran, version: version, reason: nil, options: options),
                findings: findings,
                warnings: warnings
            )
        } catch {
            return .failed(name, error: error, options: options)
        }
    }

    /// The report in `data`, or an error when its schema isn't the one read here.
    static func decode(_ data: Data) throws -> SwiftProjectLintReport {
        let decoder = JSONDecoder()
        let header: SwiftProjectLintReport.Header
        do {
            header = try decoder.decode(SwiftProjectLintReport.Header.self, from: data)
        } catch {
            throw AdapterError.unreadableOutput(name, String(describing: error))
        }
        guard header.schemaVersion == schemaVersion else {
            let found = header.schemaVersion.map(String.init) ?? "none"
            throw AdapterError.unknownSchema(name, found: found, expected: schemaVersion)
        }
        do {
            return try decoder.decode(SwiftProjectLintReport.self, from: data)
        } catch {
            throw AdapterError.unreadableOutput(name, String(describing: error))
        }
    }

    /// `issue` as a raw finding, its paths relative to `root`.
    static func finding(for issue: SwiftProjectLintReport.Issue, root: URL) -> RawFinding {
        RawFinding(
            tool: name,
            rule: issue.ruleIdentifier,
            category: issue.category,
            kind: issue.kind,
            severity: issue.severity.lowercased(),
            message: issue.message,
            symbol: issue.symbol,
            places: issue.locations.map { location in
                RawFinding.Place(
                    file: RelativePath.of(location.filePath, under: root),
                    line: location.lineNumber,
                    column: nil
                )
            }
        )
    }

    /// A warning for each rule name SwiftProjectLint said it didn't know.
    static func ruleNameWarnings(in errorText: String) -> [ScanWarning] {
        errorText.split(whereSeparator: \.isNewline)
            .filter { $0.contains("is not a rule") || $0.contains("names no known rule") }
            .map { line in
                ScanWarning(
                    file: nil,
                    message: "swiftprojectlint: " + line.trimmingCharacters(in: .whitespaces)
                )
            }
    }
}
