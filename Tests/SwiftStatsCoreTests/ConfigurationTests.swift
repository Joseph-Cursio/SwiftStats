import Foundation
@testable import SwiftStatsCore
import Testing

/// `.swiftstats.yml` (PRD §10.1) and the SwiftLint option the count honours (§7.3).
@Suite("Configuration")
struct ConfigurationTests {
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/AllKinds")

    /// A new temporary directory holding `name` with `text`.
    private static func temporaryFile(_ name: String, _ text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStatsConfig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test("excluded globs are read; keys for later milestones are accepted but unused")
    func parsing() throws {
        let configuration = try SwiftStatsConfiguration.parse(
            "excluded:\n  - Sources/Generated\nhistory:\n  window: 30d\nstore: stats.sqlite\n",
            path: "c.yml"
        )

        #expect(configuration.excluded == ["Sources/Generated"])
        #expect(configuration.unusedKeys == ["history", "store"])
        #expect(try SwiftStatsConfiguration.parse("", path: "c.yml").excluded.isEmpty)
        #expect(try SwiftStatsConfiguration.parse("---\n# nothing yet\n", path: "c.yml").excluded.isEmpty)
        let commentedOut = "excluded:\n#  - Sources/Generated\n"
        #expect(try SwiftStatsConfiguration.parse(commentedOut, path: "c.yml").excluded.isEmpty)
    }

    @Test("unknown keys, a non-list excluded, invalid YAML and a non-mapping are errors")
    func errors() {
        let cases = [
            "exclude:\n  - A\n", "excluded: Sources\n", "excluded: [\n", "- just\n- a list\n",
            "excluded:\n  - A\nexcluded:\n  - B\n", "excluded:\n  - [nested]\n"
        ]
        for text in cases {
            #expect(throws: ScanError.self) {
                try SwiftStatsConfiguration.parse(text, path: "c.yml")
            }
        }
    }

    @Test("errors say why: a missing file, and the YAML problem")
    func errorMessages() {
        let missing = URL(fileURLWithPath: "/nonexistent/swiftstats.yml")
        #expect(throws: ScanError.configurationInvalid(missing.path, "no such file")) {
            try SwiftStatsConfiguration.load(missing, root: Self.fixture)
        }
        do {
            _ = try SwiftStatsConfiguration.parse("excluded:\n  - **/Generated\n", path: "c.yml")
            Issue.record("an unquoted leading * should not parse")
        } catch {
            #expect("\(error)".contains("not valid YAML: "))
        }
    }

    @Test("a scan leaves excluded files out, lists them, and warns about unused keys")
    func scanExcludes() throws {
        let config = try Self.temporaryFile(
            ".swiftstats.yml",
            "excluded:\n  - Sources/Tool\n  - \"**/XCTestTests.swift\"\nsignals: {}\n"
        )
        let report = try PackageScanner().scan(packageAt: Self.fixture, configurationFile: config)

        let expected = ["Sources/Tool/main.swift", "Tests/AllKindsTests/XCTestTests.swift"]
        #expect(report.configuration.excludedFiles == expected)
        #expect(report.records.contains { report.configuration.excludedFiles.contains($0.file) } == false)
        #expect(report.files.map(\.path).contains("Sources/Tool/main.swift") == false)
        let warning = report.warnings.first { $0.message.hasPrefix("`signals` is accepted but not used yet") }
        #expect(warning?.file == config.path)
    }

    @Test("ignores_case_statements is read from the package's .swiftlint.yml")
    func swiftLintOption() throws {
        let enabled = try Self.temporaryFile(
            ".swiftlint.yml",
            "cyclomatic_complexity:\n  ignores_case_statements: true\n"
        )
        let unset = try Self.temporaryFile(".swiftlint.yml", "opt_in_rules: [missing_docs]\n")

        #expect(SwiftLintSettings.ignoresCaseStatements(packageRoot: enabled.deletingLastPathComponent()))
        #expect(SwiftLintSettings.ignoresCaseStatements(packageRoot: unset.deletingLastPathComponent()) == false)
        #expect(SwiftLintSettings.ignoresCaseStatements(packageRoot: Self.fixture) == false)
    }
}
