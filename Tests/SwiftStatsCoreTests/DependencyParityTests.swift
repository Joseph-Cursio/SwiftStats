//
//  DependencyParityTests.swift
//  SwiftStatsCoreTests
//
//  PRD M1b done-when (4): on two resolved packages, the direct dependencies
//  match `swift package describe` and the graph matches `swift package
//  show-dependencies`, each read here independently of SwiftStats' decoders.
//

import Foundation
import SwiftStatsCore
import Testing

@Suite(
    "Dependency parity",
    .serialized,
    .enabled(if: DependencyCorpus.isAvailable, "needs resolved swift-algorithms and SwiftCodeMetrics")
)
struct DependencyParityTests {
    /// `swift <arguments>` run in `root`, its output parsed as JSON.
    private static func swiftJSON(_ arguments: [String], in root: URL) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let start = data.firstIndex(of: UInt8(ascii: "{")) ?? data.startIndex
        return try #require(try JSONSerialization.jsonObject(with: data[start...]) as? [String: Any])
    }

    /// Every node below `node`, as identity → version.
    private static func versions(below node: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for child in node["dependencies"] as? [[String: Any]] ?? [] {
            result[child["identity"] as? String ?? ""] = child["version"] as? String
            result.merge(versions(below: child)) { first, _ in first }
        }
        return result
    }

    @Test("direct dependencies and the resolved graph match SwiftPM", arguments: DependencyCorpus.packages)
    func matchesSwiftPM(root: URL) throws {
        let report = try PackageScanner(tools: ToolLocator { $0 == "swift" ? ToolLocator.path.locate($0) : nil })
            .scan(packageAt: root)
        let described = try Self.swiftJSON(["package", "describe", "--type", "json"], in: root)
        let declared = (described["dependencies"] as? [[String: Any]] ?? []).compactMap { $0["identity"] as? String }
        let graph = try Self.swiftJSON(["package", "show-dependencies", "--format", "json"], in: root)

        #expect(declared.isEmpty == false)
        #expect(report.dependencies.direct.map(\.identity) == declared.sorted())
        let resolved = try #require(report.dependencies.resolved)
        let versions = Dictionary(uniqueKeysWithValues: resolved.packages.map { ($0.identity, $0.version) })
        #expect(versions == Self.versions(below: graph))
        #expect(Set(resolved.packages.filter(\.direct).map(\.identity)) == Set(declared))
    }
}
