import Foundation
@testable import SwiftStatsCore
import Testing

/// The SwiftLint option the SwiftLint-compatible count honours (PRD §7.3).
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
