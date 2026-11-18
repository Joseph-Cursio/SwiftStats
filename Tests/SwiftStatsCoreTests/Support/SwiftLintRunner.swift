//
//  SwiftLintRunner.swift
//  SwiftStatsCoreTests
//
//  Runs SwiftLint's `cyclomatic_complexity` alone with `warning: 0`, so it
//  reports every `func` and `init` scoring 1 or more (PRD M1a done-when).
//

import Foundation

/// Runs the installed `swiftlint` and reads its JSON report.
enum SwiftLintRunner {
    /// The SwiftLint release the SwiftLint-compatible count is checked against.
    static let referenceVersion = "0.65.1"

    /// The `swiftlint` binary, if one is on a usual path.
    static let binary: URL? = ["/opt/homebrew/bin/swiftlint", "/usr/local/bin/swiftlint"]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }

    /// Whether the reference release is installed.
    static let isAvailable: Bool = binary.flatMap { try? run($0, ["version"]) }?
        .trimmingCharacters(in: .whitespacesAndNewlines) == referenceVersion

    /// SwiftLint's complexity for every reported function, keyed by
    /// "path:line:column" of the token SwiftLint reports at.
    static func complexities(of files: [String], ignoresCaseStatements: Bool) throws -> [String: Int] {
        guard let binary else {
            return [:]
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStatsLint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent(".swiftlint.yml")
        try """
        only_rules: [cyclomatic_complexity]
        cyclomatic_complexity:
          warning: 0
          ignores_case_statements: \(ignoresCaseStatements)
        """.write(to: config, atomically: true, encoding: .utf8)
        let arguments = ["lint", "--quiet", "--no-cache", "--reporter", "json", "--config", config.path]
        let output = try run(binary, arguments + files)
        var result: [String: Int] = [:]
        for violation in try JSONDecoder().decode([SwiftLintViolation].self, from: Data(output.utf8)) {
            result["\(violation.file):\(violation.line ?? 0):\(violation.character ?? 0)"] = violation.complexity
        }
        return result
    }

    /// SwiftLint's violation count per rule for `swiftlint lint` run in
    /// `root` on `paths`, with the package's own configuration.
    static func violationCounts(in root: URL, paths: [String]) throws -> [String: Int] {
        guard let binary else {
            return [:]
        }
        let output = try run(binary, ["lint", "--reporter", "json", "--quiet", "--force-exclude"] + paths, in: root)
        let violations = try JSONDecoder().decode([SwiftLintViolation].self, from: Data(output.utf8))
        return violations.reduce(into: [:]) { counts, violation in
            counts[violation.ruleIdentifier, default: 0] += 1
        }
    }

    /// Runs the binary and returns its standard output.
    private static func run(_ binary: URL, _ arguments: [String]) throws -> String {
        try run(binary, arguments, in: nil)
    }

    /// Runs the binary in `directory`, or the current one, and returns its standard output.
    private static func run(_ binary: URL, _ arguments: [String], in directory: URL?) throws -> String {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
