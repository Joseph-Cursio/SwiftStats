import Foundation
@testable import SwiftStatsCore
import Testing

/// The SwiftLint adapter (PRD §7.7) run against a stand-in script.
@Suite("SwiftLint adapter")
struct SwiftLintAdapterTests {
    private static let source = """
    struct Store {
        func value(_ cache: [String: Int]) -> Int {
            cache["a"]!
        }
    }
    """

    private static func locator(_ tool: URL) -> ToolLocator {
        ToolLocator { $0 == "swiftlint" ? tool : nil }
    }

    /// A violation as SwiftLint's JSON reporter writes it.
    private static func violation(_ rule: String, file: String, line: String, severity: String) -> String {
        """
        {"character": 22, "file": "\(file)", "line": \(line), "reason": "\(rule) reason",
         "rule_id": "\(rule)", "severity": "\(severity)", "type": "\(rule.capitalized)"}
        """
    }

    @Test("violations attach like other findings; a whole-file one attaches to its file")
    func attachesViolations() throws {
        let package = try TemporaryPackage(["Sources/Lib/Store.swift": Self.source])
        defer { package.remove() }
        let path = package.root.appendingPathComponent("Sources/Lib/Store.swift").path
        let lint = "[" + [
            Self.violation("force_unwrapping", file: path, line: "3", severity: "Error"),
            Self.violation("file_name", file: path, line: "null", severity: "Warning")
        ].joined(separator: ",") + "]"
        let tool = try FakeTool.make(outputs: ["0.65.1\n", lint], errorText: "", statuses: [0, 2])

        let report = try package.scan(tools: Self.locator(tool))

        #expect(report.findings.map(\.rule) == ["file_name", "force_unwrapping"])
        #expect(report.findings.map(\.locations[0].attachedTo) == [.file, .function])
        #expect(report.findings.map(\.locations[0].file) == ["Sources/Lib/Store.swift", "Sources/Lib/Store.swift"])
        #expect(report.findings.map(\.severity) == ["warning", "error"])
        #expect(report.findings.allSatisfy { $0.kind == .defect && $0.tool == "swiftlint" })
        let status = try #require(report.collectors.first { $0.name == "swiftlint" })
        #expect(status.version == "0.65.1")
        #expect(status.options == ["lint --reporter json --quiet", "config: none, so SwiftLint's defaults"])
        #expect(FakeTool.arguments(of: tool) == ["version", "lint --reporter json --quiet"])
    }

    @Test("an exit status other than 0 or 2 fails the collector, not the scan")
    func failure() throws {
        let package = try TemporaryPackage([
            "Sources/Lib/Store.swift": Self.source,
            ".swiftlint.yml": "only_rules: [nope]\n"
        ])
        defer { package.remove() }
        let tool = try FakeTool.make(outputs: ["0.65.1\n", ""], errorText: "Error: bad config\n", statuses: [0, 1])

        let report = try package.scan(tools: Self.locator(tool))

        let status = try #require(report.collectors.first { $0.name == "swiftlint" })
        #expect(status.state == .failed)
        #expect(status.options.last == "config: the package's .swiftlint.yml")
        #expect(report.findings.isEmpty)
        #expect(report.rollups.allSatisfy { $0.findings["swiftlint"] == nil })
    }
}
