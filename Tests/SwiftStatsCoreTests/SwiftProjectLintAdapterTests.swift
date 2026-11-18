import Foundation
@testable import SwiftStatsCore
import Testing

/// The SwiftProjectLint adapter (PRD §7.15) run against a stand-in script.
@Suite("SwiftProjectLint adapter")
struct SwiftProjectLintAdapterTests {
    /// One issue for a canned report.
    private struct Issue {
        let rule: String
        let kind: String
        let file: String
        let line: Int

        var json: String {
            """
            {"category": "safety", "kind": "\(kind)", "locations": [{"filePath": "\(file)", "lineNumber": \(line)}],
             "message": "\(rule) here", "ruleIdentifier": "\(rule)", "ruleName": "\(rule.capitalized)",
             "severity": "Warning", "suggestion": "fix it", "symbol": "value"}
            """
        }

        init(_ rule: String, _ kind: String, _ file: String, _ line: Int) {
            self.rule = rule
            self.kind = kind
            self.file = file
            self.line = line
        }
    }

    private static let source = """
    import Foundation

    struct Store {
        var cache: [String: Int] = [:]

        func value(for key: String) -> Int {
            cache[key]!
        }
    }
    """

    private static let key = "Lib::Store::func value(for: String) -> Int"

    /// A JSON report holding `issues`, written with `schemaVersion`.
    private static func report(_ issues: [Issue], schemaVersion: Int) -> String {
        """
        {"issues": [\(issues.map(\.json).joined(separator: ","))], "schemaVersion": \(schemaVersion),
         "summary": {"totalIssues": \(issues.count)}, "tool": {"name": "SwiftProjectLint", "version": "9.9.9"}}
        """
    }

    /// A schema-1 JSON report holding `issues`.
    private static func report(_ issues: [Issue]) -> String {
        report(issues, schemaVersion: 1)
    }

    private static func locator(_ tool: URL) -> ToolLocator {
        ToolLocator { $0 == "swiftprojectlint" ? tool : nil }
    }

    @Test("findings attach to the innermost function, else the type, else the file, else outside the scan")
    func attachesFindings() throws {
        let package = try TemporaryPackage(["Sources/Lib/Store.swift": Self.source])
        defer { package.remove() }
        let tool = try FakeTool.make(
            outputs: [
            Self.report([
                Issue("forceUnwrap", "defect", "Sources/Lib/Store.swift", 7),
                Issue("couldBePrivate", "defect", "Sources/Lib/Store.swift", 3),
                Issue("todoComment", "defect", "Sources/Lib/Store.swift", 1),
                Issue("forceUnwrap", "defect", "Package.swift", 2),
                Issue("pureFunctionCandidate", "census", "Sources/Lib/Store.swift", 6)
            ]),
            Self.report([Issue("testMissingAssertion", "defect", "Sources/Lib/Store.swift", 4)])
            ],
            errorText: "",
            status: 1
        )

        let report = try package.scan(tools: Self.locator(tool))

        let attached = report.findings.map { ($0.rule, $0.locations[0].attachedTo, $0.locations[0].owner) }
        #expect(attached.map(\.0) == [
            "forceUnwrap", "todoComment", "couldBePrivate", "testMissingAssertion",
            "pureFunctionCandidate", "forceUnwrap"
        ])
        #expect(attached.map(\.1) == [.unscanned, .file, .type, .type, .function, .function])
        #expect(attached.map(\.2) == [nil, nil, "Lib::Store", "Lib::Store", Self.key, Self.key])
        #expect(report.findings.allSatisfy { $0.severity == "warning" && $0.tool == "swiftprojectlint" })
        let status = try #require(report.collectors.first { $0.name == "swiftprojectlint" })
        #expect(status.state == .ran)
        #expect(status.version == "9.9.9")
        #expect(status.options == SwiftProjectLintAdapter.options)
        let runs = FakeTool.arguments(of: tool)
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { $0.hasPrefix(package.root.path + " --format json --config ") })
    }

    @Test("roll-ups count findings by rule and kind; files outside the scan count nowhere")
    func rollups() throws {
        let package = try TemporaryPackage(["Sources/Lib/Store.swift": Self.source])
        defer { package.remove() }
        let tool = try FakeTool.make(
            outputs: [
            Self.report([
                Issue("forceUnwrap", "defect", "Sources/Lib/Store.swift", 7),
                Issue("forceUnwrap", "defect", "Package.swift", 2),
                Issue("pureFunctionCandidate", "census", "Sources/Lib/Store.swift", 6)
            ]),
            Self.report([])
            ],
            errorText: "",
            status: 0
        )

        let module = try #require(try package.scan(tools: Self.locator(tool)).rollups.first { $0.name == "Lib" })

        #expect(module.findings == ["swiftprojectlint": ["forceUnwrap": 1, "pureFunctionCandidate": 1]])
        #expect(module.findingKinds == ["swiftprojectlint": ["census": 1, "defect": 1]])
    }

    @Test("a tool that isn't found, is disabled or fails gives no counts, and says why")
    func notRun() throws {
        let package = try TemporaryPackage(["Sources/Lib/Store.swift": Self.source])
        defer { package.remove() }
        let failing = try FakeTool.make(outputs: [""], errorText: "Error: something broke\n", status: 64)
        let newer = try FakeTool.make(outputs: [Self.report([], schemaVersion: 2)], errorText: "", status: 0)

        let missing = try package.scan(tools: .nowhere)
        let failed = try package.scan(tools: Self.locator(failing))
        let unknown = try package.scan(tools: Self.locator(newer))

        for report in [missing, failed, unknown] {
            #expect(report.findings.isEmpty)
            #expect(report.rollups.allSatisfy { $0.findings.isEmpty && $0.findingKinds.isEmpty })
        }
        let states = [missing, failed, unknown].compactMap { $0.collectors.first?.state }
        #expect(states == [.skipped, .failed, .failed])
        let notFound = "`swiftprojectlint` not found on PATH; set collectors.swiftprojectlint.path"
        #expect(missing.collectors.first?.reason == notFound)
        #expect(failed.collectors.first?.reason?.contains("exited with status 64: Error: something broke") == true)
        #expect(unknown.collectors.first?.reason == "swiftprojectlint wrote schemaVersion 2; SwiftStats reads 1")
    }

    @Test("collectors.<name> can disable a tool or name its path, relative to the package root")
    func configuredTools() throws {
        let tool = try FakeTool.make(outputs: [Self.report([])], errorText: "", status: 0)
        let package = try TemporaryPackage([
            "Sources/Lib/Store.swift": Self.source,
            "bin/placeholder": "",
            ".swiftstats.yml": "collectors:\n  swiftprojectlint:\n    path: bin/missing\n"
        ])
        defer { package.remove() }
        let badPath = try package.scan(tools: Self.locator(tool))
        try "collectors:\n  swiftprojectlint:\n    enabled: false\n"
            .write(to: package.root.appendingPathComponent(".swiftstats.yml"), atomically: true, encoding: .utf8)
        let disabled = try package.scan(tools: Self.locator(tool))
        try "collectors:\n  swiftprojectlint:\n    path: \(tool.path)\n"
            .write(to: package.root.appendingPathComponent(".swiftstats.yml"), atomically: true, encoding: .utf8)
        let configured = try package.scan(tools: .nowhere)

        let notExecutable = "collectors.swiftprojectlint.path bin/missing is not an executable file"
        #expect(badPath.collectors.first?.reason == notExecutable)
        #expect(disabled.collectors.first?.reason == "disabled by collectors.swiftprojectlint.enabled")
        #expect(configured.collectors.first?.state == .ran)
    }

    @Test("rule names SwiftProjectLint doesn't know become warnings")
    func ruleNameWarnings() {
        let stderr = """
        Warning: /tmp/c.yml has 1 problem that changes which rules run.
          enabled_only: 'Test Missing Asertion' is not a rule, so it is ignored. Did you mean 'Test Missing Assertion'?
        """
        #expect(SwiftProjectLintAdapter.ruleNameWarnings(in: stderr).map(\.message) == [
            "swiftprojectlint: enabled_only: 'Test Missing Asertion' is not a rule, so it is ignored. "
                + "Did you mean 'Test Missing Assertion'?"
        ])
    }

    @Test("absolute paths inside the root become relative; others stay as given")
    func relativePaths() {
        let root = URL(fileURLWithPath: "/work/Package")
        #expect(RelativePath.of("/work/Package/Sources/A.swift", under: root) == "Sources/A.swift")
        #expect(RelativePath.of("./Sources/A.swift", under: root) == "Sources/A.swift")
        #expect(RelativePath.of("/elsewhere/A.swift", under: root) == "/elsewhere/A.swift")
    }
}
