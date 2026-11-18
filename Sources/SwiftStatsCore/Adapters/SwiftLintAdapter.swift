//
//  SwiftLintAdapter.swift
//  SwiftStatsCore
//
//  Runs SwiftLint's normal rules with the package's own configuration and
//  reads its JSON (PRD §7.7). The counts match a plain `swiftlint lint` in
//  the package root, so they can be checked against it.
//

import Foundation

/// The SwiftLint adapter.
enum SwiftLintAdapter {
    /// The collector's name.
    static let name = "swiftlint"
    /// SwiftLint's exit status when it found serious violations.
    private static let foundErrors: Int32 = 2
    /// The lint run's arguments.
    static let lintArguments = ["lint", "--reporter", "json", "--quiet"]

    /// Runs `executable` in the package at `root`.
    static func run(executable: URL, root: URL) -> AdapterResult {
        let hasConfig = FileManager.default.fileExists(atPath: root.appendingPathComponent(".swiftlint.yml").path)
        let options = [
            lintArguments.joined(separator: " "),
            hasConfig ? "config: the package's .swiftlint.yml" : "config: none, so SwiftLint's defaults"
        ]
        do {
            let versionOutput = try ProcessRunner.run(executable: executable.path, arguments: ["version"], in: root)
            let version = String(bytes: versionOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let output = try ProcessRunner.run(
                executable: executable.path,
                arguments: lintArguments,
                in: root,
                accepting: [0, foundErrors]
            )
            return AdapterResult(
                status: CollectorStatus(name: name, state: .ran, version: version, reason: nil, options: options),
                findings: try decode(output.output).map { finding(for: $0, root: root) },
                warnings: []
            )
        } catch {
            return .failed(name, error: error, options: options)
        }
    }

    /// The violations in `data`.
    static func decode(_ data: Data) throws -> [SwiftLintViolationRecord] {
        do {
            return try JSONDecoder().decode([SwiftLintViolationRecord].self, from: data)
        } catch {
            throw AdapterError.unreadableOutput(name, String(describing: error))
        }
    }

    /// `violation` as a raw finding, its path relative to `root`.
    static func finding(for violation: SwiftLintViolationRecord, root: URL) -> RawFinding {
        RawFinding(
            tool: name,
            rule: violation.ruleIdentifier,
            category: nil,
            kind: .defect,
            severity: violation.severity.lowercased(),
            message: violation.reason,
            symbol: nil,
            places: [
                RawFinding.Place(
                    file: violation.file.map { RelativePath.of($0, under: root) } ?? "",
                    line: violation.line,
                    column: violation.character
                )
            ]
        )
    }
}
