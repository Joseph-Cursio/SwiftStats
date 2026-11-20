import Foundation
@testable import SwiftStatsCore
import Testing

/// How SwiftInferProperties runs (PRD §7.11, §6.5): once per production
/// target in its own clone of a temporary copy, with its own `TMPDIR`; what
/// the copy holds; how the targets' indexes merge; and how a run fails.
@Suite("SwiftInferProperties runs")
struct SwiftInferRunTests {
    /// An empty index for each indexed target but those in `indexes`.
    private static func indexes(_ indexes: [String: String]) -> [String: String] {
        ["Core": PropertyHarness.emptyIndex, "Macros": PropertyHarness.emptyIndex, "Tool": PropertyHarness.emptyIndex]
            .merging(indexes) { _, given in given }
    }

    /// Every file under `root` with its contents, or a symlink's destination.
    private static func listing(_ root: URL) -> [String: String] {
        let paths = FileManager.default.subpaths(atPath: root.path) ?? []
        var listing: [String: String] = [:]
        for path in paths {
            let url = root.appendingPathComponent(path)
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                listing[path] = "-> " + destination
            } else if let data = FileManager.default.contents(atPath: url.path) {
                listing[path] = String(bytes: data, encoding: .utf8) ?? "<binary>"
            }
        }
        return listing
    }

    @Test("""
        each production library, macro and executable target runs in its own copy with its own TMPDIR; \
        a plugin never does
        """)
    func perTarget() throws {
        let package = try PropertyHarness.package([:])
        defer { package.remove() }
        let tool = try FakeTool.makeIndexer(indexes: Self.indexes([:]), errors: [:], statuses: [:], delays: [:])
        defer { PropertyHarness.remove(tool) }

        let report = try package.scan(tools: PropertyHarness.locator(tool))

        let status = try #require(PropertyHarness.status(report))
        #expect(status.state == .ran)
        #expect(status.version == "9.9.9 (fake build)")
        #expect(status.options == [
            "skippedTargets: Plug (plugin)",
            "flags: index defaults (Possible included)",
            "copy: target files after exclusion, no index or decisions",
            "universe: all targets after exclusion",
            "config.toml: absent",
            "vocabulary.json: absent",
            ".swift-version: absent",
            "targets: Core, Macros, Tool"
        ])
        #expect(FakeTool.arguments(of: tool).sorted() == [
            "index --target Core", "index --target Macros", "index --target Tool"
        ])
        let runs = FakeTool.log("runs.log", of: tool).map { $0.split(separator: " ").map(String.init) }
        #expect(runs.map { $0[0] }.sorted() == ["Core", "Macros", "Tool"])
        let directories = runs.map { $0[1] }
        let temporaries = runs.map { $0[2] }
        #expect(Set(directories).count == 3 && Set(temporaries).count == 3)
        #expect(directories.allSatisfy { $0.hasSuffix("/package") && $0.hasPrefix(package.root.path) == false })
        #expect(temporaries.allSatisfy { $0.hasSuffix("/tmp/") })
        #expect(directories.allSatisfy { FileManager.default.fileExists(atPath: $0) == false })
        #expect(temporaries.allSatisfy { FileManager.default.fileExists(atPath: $0) == false })
        #expect(report.properties?.candidates.isEmpty == true)
        #expect(report.rollups.allSatisfy { $0.properties == nil })
    }

    @Test("""
        the copy holds the manifest and its versioned ones, pins, toolchain pin, every target's files after \
        exclusion and the settings, never an index, decisions or verify evidence, and the package is left \
        untouched
        """)
    func copyContents() throws {
        let config = "[discover]\npacks = [\"algebraic\"]\n"
        var targets = PropertyHarness.targets
        targets[0] = PropertyHarness.target("Core", "library", "Sources/Core", [
            "Linked.swift", "Skipped.swift", "Values.swift"
        ])
        let package = try TemporaryPackage(PropertyHarness.files.merging([
            ".swiftinfer/config.toml": config,
            ".swiftinfer/index.json": "stale",
            ".swiftinfer/decisions.json": "{}",
            ".swiftinfer/verify-evidence.json": "{}",
            ".swift-version": "6.4.1\n",
            ".swiftstats.yml": "excluded:\n  - Sources/Core/Skipped.swift\n",
            "Package.resolved": "{}\n",
            "Package@swift-6.0.swift": "// swift-tools-version: 6.0\n",
            "Shared/Linked.swift": "func linked() {}\n",
            "Sources/Core/README.md": "notes\n",
            "Sources/Core/Skipped.swift": "func skipped() {}\n"
        ]) { _, new in new }, targets: targets)
        defer { package.remove() }
        try FileManager.default.createSymbolicLink(
            atPath: package.root.appendingPathComponent("Sources/Core/Linked.swift").path,
            withDestinationPath: "../../Shared/Linked.swift"
        )
        let before = Self.listing(package.root)
        let tool = try FakeTool.makeIndexer(indexes: Self.indexes([:]), errors: [:], statuses: [:], delays: [:])
        defer { PropertyHarness.remove(tool) }

        let report = try package.scan(tools: PropertyHarness.locator(tool))

        #expect(FakeTool.log("files-Core.txt", of: tool) == [
            "./.swift-version", "./.swiftinfer/config.toml", "./Package.resolved", "./Package.swift",
            "./Package@swift-6.0.swift", "./Plugins/Plug/Plugin.swift", "./Sources/Core/Linked.swift",
            "./Sources/Core/Values.swift", "./Sources/Macros/Macro.swift", "./Sources/Tool/main.swift",
            "./Tests/CoreTests/MoneyTests.swift"
        ])
        #expect(FakeTool.log("swift-version-Tool.txt", of: tool) == ["6.4.1"])
        let options = PropertyHarness.status(report)?.options ?? []
        #expect(options.contains("config.toml: sha256:\(ContentHash.sha256(Data(config.utf8)))"))
        #expect(options.contains("vocabulary.json: absent"))
        #expect(options.contains(".swift-version: 6.4.1"))
        #expect(Self.listing(package.root) == before)
    }

    @Test("""
        one identity from two targets keeps the blocked row at a shared location, both rows at two \
        locations and one of two equal rows, whichever target finishes first
        """)
    func mergeOrder() throws {
        let values = "@ROOT@/Sources/Core/Values.swift:4"
        let core = PropertyHarness.index([
            PropertyHarness.Row(identity: "0x00000000000000AA", location: values),
            PropertyHarness.Row(identity: "0x00000000000000BB", location: values),
            PropertyHarness.Row(identity: "0x00000000000000CC", location: values, seen: "2026-11-19T01:00:00Z")
        ])
        let other = PropertyHarness.index([
            PropertyHarness.Row(identity: "0x00000000000000AA", location: values, blocker: "\"caseless carrier\""),
            PropertyHarness.Row(identity: "0x00000000000000BB", location: "@ROOT@/Sources/Tool/main.swift:1"),
            PropertyHarness.Row(identity: "0x00000000000000CC", location: values, seen: "2026-11-19T02:00:00Z")
        ])
        let package = try PropertyHarness.package([:])
        defer { package.remove() }
        var results: [PropertyReport] = []
        for slow in ["Core", "Tool"] {
            let tool = try FakeTool.makeIndexer(
                indexes: Self.indexes(["Core": core, "Tool": other]),
                errors: [:],
                statuses: [:],
                delays: [slow: 0.5]
            )
            defer { PropertyHarness.remove(tool) }
            results.append(try #require(try package.scan(tools: PropertyHarness.locator(tool)).properties))
        }

        #expect(results[0] == results[1])
        let merged = results[0]
        #expect((merged.crossTargetDuplicates, merged.crossTargetConflicts, merged.identityCollisions) == (1, 1, 1))
        let byIdentity = Dictionary(grouping: merged.candidates, by: \.identity)
        #expect(byIdentity["0x00000000000000AA"]?.map(\.blocked) == [true])
        #expect(byIdentity["0x00000000000000BB"]?.map(\.identityCollision) == [true, true])
        #expect(byIdentity["0x00000000000000BB"]?.compactMap(\.location?.file)
            == ["Sources/Core/Values.swift", "Sources/Tool/main.swift"])
        #expect(byIdentity["0x00000000000000CC"]?.map(\.identityCollision) == [false])
    }

    @Test("""
        exit 64 and an index of schema 6 fail the collector with no suggestions, and the failure \
        names the copy generically, so two runs give one reason
        """)
    func failures() throws {
        let package = try PropertyHarness.package([:])
        defer { package.remove() }
        let failing = try FakeTool.makeIndexer(
            indexes: Self.indexes([:]),
            errors: ["Core": "note: scratch at @TMP@manifest\nerror: no target at @ROOT@/Sources/Core\n"],
            statuses: ["Core": 64],
            delays: [:]
        )
        defer { PropertyHarness.remove(failing) }
        let newer = try FakeTool.makeIndexer(
            indexes: Self.indexes(["Core": PropertyHarness.index([], interactions: [], schemaVersion: 6)]),
            errors: [:],
            statuses: [:],
            delays: [:]
        )
        defer { PropertyHarness.remove(newer) }

        let first = try package.scan(tools: PropertyHarness.locator(failing))
        let second = try package.scan(tools: PropertyHarness.locator(failing))
        let unknown = try package.scan(tools: PropertyHarness.locator(newer))

        for report in [first, second, unknown] {
            #expect(PropertyHarness.status(report)?.state == .failed)
            #expect(PropertyHarness.status(report)?.version == nil)
            #expect(PropertyHarness.status(report)?.options.last == "targets: Core, Macros, Tool")
            #expect(report.properties == nil)
            #expect(report.rollups.allSatisfy { $0.properties == nil })
        }
        let reason = try #require(PropertyHarness.status(first)?.reason)
        #expect(reason == PropertyHarness.status(second)?.reason)
        #expect(reason.contains("index --target Core` exited with status 64:"))
        #expect(reason.contains("note: scratch at <tmp>/manifest\nerror: no target at <copy>/Sources/Core"))
        #expect(reason.contains("/targets/") == false)
        #expect(PropertyHarness.status(unknown)?.reason
            == "swiftinferproperties wrote schemaVersion 6; SwiftStats reads 5")
    }

    @Test("two scans of one package give the same report; a disabled collector never runs; a configured path does")
    func repeatableAndConfigured() throws {
        let row = PropertyHarness.Row(identity: "0x00000000000000AA", location: "@ROOT@/Sources/Core/Values.swift:4")
        let tool = try FakeTool.makeIndexer(
            indexes: Self.indexes(["Core": PropertyHarness.index([row])]),
            errors: [:],
            statuses: [:],
            delays: [:]
        )
        defer { PropertyHarness.remove(tool) }
        let package = try PropertyHarness.package([:])
        defer { package.remove() }
        let disabled = try PropertyHarness.package([
            ".swiftstats.yml": "collectors:\n  swiftinferproperties:\n    enabled: false\n"
        ])
        defer { disabled.remove() }
        let configured = try PropertyHarness.package([
            ".swiftstats.yml": "collectors:\n  swiftinferproperties:\n    path: \(tool.path)\n"
        ])
        defer { configured.remove() }

        let first = try package.scan(tools: PropertyHarness.locator(tool))
        let second = try package.scan(tools: PropertyHarness.locator(tool))
        let runsBefore = FakeTool.arguments(of: tool).count
        let off = try disabled.scan(tools: PropertyHarness.locator(tool))
        let runsAfter = FakeTool.arguments(of: tool).count
        let byPath = try configured.scan(tools: .nowhere)

        #expect(try ScanReportEncoder.encode(first) == ScanReportEncoder.encode(second))
        #expect(first.properties?.candidates.count == 1)
        #expect(runsAfter == runsBefore)
        #expect(PropertyHarness.status(off)?.state == .skipped)
        #expect(PropertyHarness.status(off)?.reason == "disabled by collectors.swiftinferproperties.enabled")
        #expect(off.properties == nil)
        #expect(PropertyHarness.status(byPath)?.state == .ran)
        #expect(byPath.properties?.candidates.map(\.identity) == ["0x00000000000000AA"])
    }
}
