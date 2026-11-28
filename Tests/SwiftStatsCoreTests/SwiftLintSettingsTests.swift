import Foundation
@testable import SwiftStatsCore
import Testing

/// `cyclomatic_complexity.ignores_case_statements` in the package's
/// `.swiftlint.yml` (PRD §7.3): read as Yams' `load` reads it, without
/// building the file's other values, since `load` traps on a base-60
/// integer past `Int` or a key that isn't text (design B30's class).
@Suite("SwiftLint settings")
struct SwiftLintSettingsTests {
    /// A `cyclomatic_complexity` entry that doesn't ignore case statements.
    private static let falseRule = "cyclomatic_complexity: {ignores_case_statements: false}\n"

    /// Whether a package whose `.swiftlint.yml` holds `text` ignores case
    /// statements.
    private static func ignoresCases(_ text: String) throws -> Bool {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStatsLint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try text.write(to: directory.appendingPathComponent(".swiftlint.yml"), atomically: true, encoding: .utf8)
        return SwiftLintSettings.ignoresCaseStatements(packageRoot: directory)
    }

    @Test(
        """
        ignores_case_statements reads as Yams' load reads it: a YAML 1.1 boolean, keys by their text whatever \
        their quotes or tag, an alias, merge keys under an own key, the last of a repeat by text
        """,
        arguments: [
            ("cyclomatic_complexity:\n  ignores_case_statements: true\n", true),
            ("cyclomatic_complexity: {ignores_case_statements: Yes}\n", true),
            ("cyclomatic_complexity:\n  ignores_case_statements: \"true\"\n", false),
            ("cyclomatic_complexity: {ignores_case_statements: !!str true}\n", false),
            ("cyclomatic_complexity: {ignores_case_statements: !t true}\n", false),
            ("cyclomatic_complexity: {ignores_case_statements: tRuE}\n", false),
            ("cyclomatic_complexity: {ignores_case_statements: !!bool 1}\n", false),
            ("'cyclomatic_complexity': {\"ignores_case_statements\": on}\n", true),
            ("!t cyclomatic_complexity: {!t ignores_case_statements: true}\n", true),
            ("base: &b {ignores_case_statements: true}\ncyclomatic_complexity: *b\n", true),
            ("cyclomatic_complexity:\n  <<: {ignores_case_statements: true}\n  warning: 12\n", true),
            ("cyclomatic_complexity: {<<: {ignores_case_statements: true}, ignores_case_statements: false}\n", false),
            ("<<: {cyclomatic_complexity: {ignores_case_statements: true}}\n", true),
            ("<<: [{cyclomatic_complexity: {ignores_case_statements: true}}, {cyclomatic_complexity: {}}]\n", true),
            ("cyclomatic_complexity: !!set {ignores_case_statements: true}\n", false),
            (falseRule + "!t cyclomatic_complexity: {ignores_case_statements: true}\n", true),
            ("cyclomatic_complexity: {ignores_case_statements: true}\n" + falseRule, false),
            ("- cyclomatic_complexity: {ignores_case_statements: true}\n", false),
            ("cyclomatic_complexity: {ignores_case_statements: true}\n---\nx: 1\n", false)
        ]
    )
    func readsAsYamsLoads(text: String, ignores: Bool) throws {
        #expect(try Self.ignoresCases(text) == ignores)
    }

    @Test(
        """
        a base-60 integer past Int or a key that isn't text anywhere in .swiftlint.yml is not read, so it doesn't \
        trap the scan, and ignores_case_statements beside it is still read (design B30)
        """,
        arguments: [
            ("line_length: 1:0:0:0:0:0:0:0:0:0:0\ncyclomatic_complexity:\n  ignores_case_statements: true\n", true),
            ("cyclomatic_complexity: {ignores_case_statements: true}\nx: 9223372036854775807:0\n", true),
            ("? [a]\n: b\ncyclomatic_complexity: {ignores_case_statements: true}\n", true),
            ("cyclomatic_complexity: {ignores_case_statements: 1:0:0:0:0:0:0:0:0:0:0}\n", false)
        ]
    )
    func valuesYamsTrapsOnAreNotRead(text: String, ignores: Bool) throws {
        #expect(try Self.ignoresCases(text) == ignores)
    }
}
