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

    @Test("excluded globs and the store are read; keys for later milestones are accepted but unused")
    func parsing() throws {
        let configuration = try SwiftStatsConfiguration.parse(
            "excluded:\n  - Sources/Generated\nhistory:\n  window: 30d\nstore: stats.sqlite\n",
            path: "c.yml"
        )

        #expect(configuration.excluded == ["Sources/Generated"])
        #expect(configuration.unusedKeys == ["history"])
        #expect(configuration.store == "stats.sqlite")
        #expect(try SwiftStatsConfiguration.parse("", path: "c.yml").store == nil)
        #expect(try SwiftStatsConfiguration.parse("", path: "c.yml").excluded.isEmpty)
        #expect(try SwiftStatsConfiguration.parse("---\n# nothing yet\n", path: "c.yml").excluded.isEmpty)
        let commentedOut = "excluded:\n#  - Sources/Generated\n"
        #expect(try SwiftStatsConfiguration.parse(commentedOut, path: "c.yml").excluded.isEmpty)
    }

    @Test("unknown keys, a non-list excluded, a non-path store, invalid YAML and a non-mapping are errors")
    func errors() {
        let cases = [
            "exclude:\n  - A\n", "excluded: Sources\n", "excluded: [\n", "- just\n- a list\n",
            "excluded:\n  - A\nexcluded:\n  - B\n", "excluded:\n  - [nested]\n", "store:\n  - a\n", "store: \"\"\n"
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

    @Test("a key given twice, and a file that isn't UTF-8, are errors that say so")
    func moreErrorMessages() throws {
        do {
            _ = try SwiftStatsConfiguration.parse("excluded:\n  - A\nexcluded:\n  - B\n", path: "c.yml")
            Issue.record("a repeated key should not parse")
        } catch {
            // Yams rejects the repeat before SwiftStats sees the mapping.
            #expect("\(error)".hasPrefix("c.yml: not valid YAML: "))
            #expect("\(error)".contains("duplicated key(s): 'excluded'"))
        }
        let latin1 = try Self.temporaryFile(".swiftstats.yml", "")
        try Data([0x65, 0x78, 0xFF, 0x3A]).write(to: latin1)
        #expect(throws: ScanError.configurationInvalid(latin1.path, "not readable as UTF-8")) {
            try SwiftStatsConfiguration.load(latin1, root: latin1.deletingLastPathComponent())
        }
    }

    @Test("collectors: enabled and path are read; options and later collectors are accepted but unused")
    func collectors() throws {
        let text = """
        collectors:
          swiftlint:
            enabled: false
          swiftprojectlint:
            path: tools/spl
            options: [--strict]
          swiftmutator:
            enabled: true
          dependencies:
        """
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")

        #expect(configuration.collectors == [
            "dependencies": CollectorSettings(enabled: true, path: nil),
            "swiftlint": CollectorSettings(enabled: false, path: nil),
            "swiftprojectlint": CollectorSettings(enabled: true, path: "tools/spl")
        ])
        #expect(configuration.unusedKeys == ["collectors.swiftmutator", "collectors.swiftprojectlint.options"])
        let invalid = [
            "collectors: [swiftlint]\n", "collectors:\n  swiftlint: on\n",
            "collectors:\n  swiftlint:\n    enabled: maybe\n", "collectors:\n  swiftlint:\n    paths: x\n",
            "collectors:\n  swiftlint:\n    path: [x]\n"
        ]
        for entry in invalid {
            #expect(throws: ScanError.self, "\(entry)") {
                try SwiftStatsConfiguration.parse(entry, path: "c.yml")
            }
        }
    }

    @Test("a scan leaves excluded files out, lists them, and warns about unused keys")
    func scanExcludes() throws {
        let config = try Self.temporaryFile(
            ".swiftstats.yml",
            "excluded:\n  - Sources/Tool\n  - \"**/XCTestTests.swift\"\nsignals: {}\n"
        )
        let report = try PackageScanner(tools: .nowhere).scan(packageAt: Self.fixture, configurationFile: config)

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
        let otherOptions = try Self.temporaryFile(".swiftlint.yml", "cyclomatic_complexity:\n  warning: 12\n")
        let invalid = try Self.temporaryFile(".swiftlint.yml", "cyclomatic_complexity: [\n")

        #expect(SwiftLintSettings.ignoresCaseStatements(packageRoot: enabled.deletingLastPathComponent()))
        #expect(SwiftLintSettings.ignoresCaseStatements(packageRoot: unset.deletingLastPathComponent()) == false)
        #expect(SwiftLintSettings.ignoresCaseStatements(packageRoot: Self.fixture) == false)
        #expect(SwiftLintSettings.ignoresCaseStatements(packageRoot: otherOptions.deletingLastPathComponent()) == false)
        #expect(SwiftLintSettings.ignoresCaseStatements(packageRoot: invalid.deletingLastPathComponent()) == false)
    }
}
