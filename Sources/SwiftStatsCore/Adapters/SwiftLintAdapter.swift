//
//  SwiftLintAdapter.swift
//  SwiftStatsCore
//
//  Runs SwiftLint's normal rules with the package's own configuration and
//  reads its JSON (PRD §7.7). It lints the targets' directories, not the
//  whole package root, which would take in `.build/checkouts`, worktrees and
//  other packages; `--force-exclude` keeps the configuration's `excluded`
//  in force for paths given this way. The configuration is always named
//  with `--config`, the package's root `.swiftlint.yml` or an empty one,
//  because otherwise SwiftLint also applies any `.swiftlint.yml` in the
//  directories above the package.
//

import Foundation

/// The SwiftLint adapter.
enum SwiftLintAdapter {
    /// The collector's name.
    static let name = "swiftlint"
    /// SwiftLint's exit status when it found serious violations.
    private static let foundErrors: Int32 = 2
    /// The lint run's arguments before the paths.
    static let lintArguments = ["lint", "--reporter", "json", "--quiet", "--force-exclude"]

    /// The configuration file SwiftLint reads at a package's root.
    static let configurationName = ".swiftlint.yml"
    /// How the empty configuration is shown in the collector's options.
    static let emptyConfigurationLabel = "<empty>"

    /// The paths linted, sorted: each target's directory, or a root
    /// target's own files, leaving out any inside another path given, since
    /// SwiftLint lints a file once for each path that holds it.
    static func paths(of targets: [TargetSummary]) -> [String] {
        let candidates = Set(targets.flatMap { $0.path.isEmpty ? $0.files : [$0.path] })
        return candidates
            .filter { path in candidates.contains { path.hasPrefix($0 + "/") } == false }
            .sorted()
    }

    /// Runs `executable` in the package at `root` on `targets`' directories.
    static func run(executable: URL, root: URL, targets: [TargetSummary]) -> AdapterResult {
        let hasConfig = FileManager.default.fileExists(atPath: root.appendingPathComponent(configurationName).path)
        let paths = paths(of: targets)
        let shownConfig = hasConfig ? configurationName : emptyConfigurationLabel
        let options = [
            (lintArguments + ["--config", shownConfig] + paths).joined(separator: " "),
            hasConfig ? "config: the package's .swiftlint.yml" : "config: none, so SwiftLint's defaults"
        ]
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftStats-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let config: String
            if hasConfig {
                config = configurationName
            } else {
                let empty = directory.appendingPathComponent("swiftlint.yml")
                try "disabled_rules: []\n".write(to: empty, atomically: true, encoding: .utf8)
                config = empty.path
            }
            let versionOutput = try ProcessRunner.run(executable: executable.path, arguments: ["version"], in: root)
            let version = String(bytes: versionOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let output = try ProcessRunner.run(
                executable: executable.path,
                arguments: lintArguments + ["--config", config] + paths,
                in: root,
                accepting: [0, foundErrors]
            )
            return AdapterResult(
                status: CollectorStatus(name: name, state: .ran, version: version, reason: nil, options: options),
                findings: try decode(output.output).map { finding(for: $0, root: root) },
                warnings: nestedConfigurationWarnings(root: root, paths: paths)
            )
        } catch {
            return .failed(name, error: error, options: options)
        }
    }

    /// A warning when a linted directory holds its own `.swiftlint.yml`,
    /// which SwiftLint ignores once `--config` names a configuration.
    static func nestedConfigurationWarnings(root: URL, paths: [String]) -> [ScanWarning] {
        let nested = paths.flatMap { path -> [String] in
            let directory = root.appendingPathComponent(path)
            guard let walker = FileManager.default.enumerator(atPath: directory.path) else {
                return []
            }
            return walker.compactMap { $0 as? String }
                .filter { $0 == configurationName || $0.hasSuffix("/" + configurationName) }
                .map { path + "/" + $0 }
        }
        guard nested.isEmpty == false else {
            return []
        }
        let message = "swiftlint: nested configurations are not applied, only the root one: "
            + nested.sorted().joined(separator: ", ")
        return [ScanWarning(file: nil, message: message)]
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
