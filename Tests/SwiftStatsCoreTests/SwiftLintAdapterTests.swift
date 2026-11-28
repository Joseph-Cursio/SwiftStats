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
        #expect(status.options == [
            "lint --reporter json --quiet --force-exclude --config <empty> Sources/Lib",
            "config: none, so SwiftLint's defaults"
        ])
        let arguments = FakeTool.arguments(of: tool)
        #expect(arguments.first == "version")
        // An empty configuration of SwiftStats' own, so no .swiftlint.yml above the package applies.
        #expect(arguments.last?.hasPrefix("lint --reporter json --quiet --force-exclude --config /") == true)
        #expect(arguments.last?.hasSuffix("/swiftlint.yml Sources/Lib") == true)
        #expect(report.warnings.isEmpty)
        let config = try #require(FakeTool.configPaths(of: tool).last)
        let scratch = URL(fileURLWithPath: config).deletingLastPathComponent()
        #expect(scratch.lastPathComponent.hasPrefix("SwiftStats-"))
        #expect(FileManager.default.fileExists(atPath: scratch.path) == false)
    }

    @Test("the scratch folder of SwiftStats' empty configuration is registered for an interrupt while SwiftLint runs")
    func scratchRegistered() async throws {
        let package = try TemporaryPackage(["Sources/Lib/Store.swift": Self.source])
        defer { package.remove() }
        let tool = try FakeTool.make(outputs: ["0.65.1\n", "[]"], errorText: "", statuses: [0])
        let hold = try FakeTool.hold(tool)
        defer { try? FileManager.default.removeItem(at: hold) }
        let root = package.root
        let run = Task.detached { _ = SwiftLintAdapter.run(executable: tool, root: root, targets: []) }

        let started = try await FakeTool.firstRun(of: tool)
        let registered = ScratchRegistry.shared.registeredPaths.map(\.path)
        try FileManager.default.removeItem(at: hold)
        await run.value

        let config = try #require(FakeTool.configPaths(of: tool).last)
        #expect(started)
        #expect(registered.contains(URL(fileURLWithPath: config).deletingLastPathComponent().path))
    }

    @Test("the package's own configuration is named, and nested ones are reported as not applied")
    func packageConfiguration() throws {
        let package = try TemporaryPackage([
            "Sources/Lib/Store.swift": Self.source,
            "Tests/LibTests/StoreTests.swift": "",
            "Tests/LibTests/.swiftlint.yml": "disabled_rules: [force_unwrapping]\n",
            ".swiftlint.yml": "opt_in_rules: [force_unwrapping]\n"
        ])
        defer { package.remove() }
        let tool = try FakeTool.make(outputs: ["0.65.1\n", "[]"], errorText: "", statuses: [0])

        let report = try package.scan(tools: Self.locator(tool))

        let lint = "lint --reporter json --quiet --force-exclude --config .swiftlint.yml Sources/Lib Tests/LibTests"
        #expect(FakeTool.arguments(of: tool) == ["version", lint])
        let status = try #require(report.collectors.first { $0.name == "swiftlint" })
        #expect(status.options == [lint, "config: the package's .swiftlint.yml"])
        #expect(report.warnings.map(\.message) == [
            "swiftlint: nested configurations are not applied, only the root one: Tests/LibTests/.swiftlint.yml"
        ])
    }

    @Test("a path inside another is dropped, and a target at the root gives its files, not the root")
    func overlappingPaths() {
        let target = { (name: String, path: String, files: [String]) in
            TargetSummary(name: name, type: "library", isTest: false, path: path, files: files)
        }
        let nested = [
            target("Foo", "Sources/Foo", ["Sources/Foo/Foo.swift"]),
            target("Bar", "Sources/Foo/Bar", ["Sources/Foo/Bar/Bar.swift"]),
            target("Foobar", "Sources/Foobar", ["Sources/Foobar/Foobar.swift"])
        ]
        let atRoot = [
            target("Lib", "", ["Lib.swift", "Support/Helpers.swift"]),
            target("LibTests", "Tests/LibTests", ["Tests/LibTests/LibTests.swift"])
        ]

        #expect(SwiftLintAdapter.paths(of: nested) == ["Sources/Foo", "Sources/Foobar"])
        #expect(SwiftLintAdapter.paths(of: atRoot) == ["Lib.swift", "Support/Helpers.swift", "Tests/LibTests"])
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
