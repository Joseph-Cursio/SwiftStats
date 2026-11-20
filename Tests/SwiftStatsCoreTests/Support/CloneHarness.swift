//
//  CloneHarness.swift
//  SwiftStatsCoreTests
//
//  Scans the Clones fixture with a fixed description (libraries `Core`
//  and `Extras`, test target `CoreTests`) and a fake SwiftCloneDetector
//  serving the JSON the real tool wrote for each pass over the fixture's
//  production files, kept in `Recorded/`.
//

import Foundation
@testable import SwiftStatsCore

/// Scans the Clones fixture with recorded SwiftCloneDetector output.
enum CloneHarness {
    /// The fixture package.
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Clones")

    /// The fixture's real path, as a tool's `pwd -P` prints it. Not
    /// `resolvingSymlinksInPath()`, which drops a leading `/private`, so a
    /// checkout under `/tmp` or `/var` would never match.
    static var fixtureRealPath: String {
        guard let real = realpath(fixture.path, nil) else {
            return fixture.path
        }
        defer { free(real) }
        return String(cString: real)
    }

    /// The files the tool reads: production, not generated, byte-sorted.
    static let files = [
        "Sources/Core/Parsing.swift", "Sources/Core/Paths.swift", "Sources/Core/Reports.swift",
        "Sources/Core/Shapes.swift", "Sources/Core/Totals.swift", "Sources/Extras/Boxes.swift",
        "Sources/Extras/Codes.swift", "Sources/Extras/Ledger.swift"
    ]

    /// The fixture's targets: name, SwiftPM type and directory.
    private static let targets = [
        ("Core", "library", "Sources/Core"),
        ("Extras", "library", "Sources/Extras"),
        ("CoreTests", "test", "Tests/CoreTests")
    ]

    /// The fixture's description.
    static var package: DescribedPackage {
        DescribedPackage(name: "Clones", targets: targets.map { name, type, path in
            DescribedTarget(name: name, type: type, moduleType: "SwiftTarget", path: path, sources: sources(in: path))
        })
    }

    /// The recorded JSON of the run `name`: `default`, `type3`, `sequence`,
    /// `type1`, or the tool's own merge, `all`.
    static func recorded(_ name: String) throws -> String {
        try String(contentsOf: fixture.appendingPathComponent("Recorded/\(name).json"), encoding: .utf8)
    }

    /// The recorded run `name`, decoded.
    static func output(_ name: String) throws -> CloneDetectorOutput {
        try JSONDecoder().decode(CloneDetectorOutput.self, from: Data(recorded(name).utf8))
    }

    /// The recorded output of each pass, keyed as the fake tool names runs.
    static func outputs() throws -> [String: String] {
        [
            "default": try recorded("default"),
            "--type3": try recorded("type3"),
            "--sequence": try recorded("sequence"),
            "--type1": try recorded("type1")
        ]
    }

    /// A fake tool serving every pass's recorded output.
    static func recordedTool() throws -> URL {
        try FakeTool.makeCloneDetector(outputs: outputs(), errors: [:], statuses: [:])
    }

    /// A locator that finds `tool` as `swift-clone-detector`, and nothing else.
    static func locator(_ tool: URL) -> ToolLocator {
        ToolLocator { $0 == SwiftCloneDetectorAdapter.executableName ? tool : nil }
    }

    /// The fixture scanned with `tool` as the clone detector.
    static func scan(_ tool: URL) throws -> ScanReport {
        try PackageScanner(describer: FixedDescriber(package: package), tools: locator(tool)).scan(packageAt: fixture)
    }

    /// The SwiftCloneDetector collector's status in `report`.
    static func status(_ report: ScanReport) -> CollectorStatus? {
        report.collectors.first { $0.name == SwiftCloneDetectorAdapter.name }
    }

    /// The arguments the fake tool at `tool` got for the run `name`.
    static func arguments(of tool: URL, run name: String) -> [String] {
        FakeTool.log("arguments-\(name).txt", of: tool)
    }

    /// Removes the fake tool at `tool` and its logs.
    static func remove(_ tool: URL) {
        try? FileManager.default.removeItem(at: tool.deletingLastPathComponent())
    }

    /// The Swift files under the fixture's `path`, relative to it, sorted.
    private static func sources(in path: String) -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: fixture.appendingPathComponent(path).path)
        let paths = (enumerator?.allObjects as? [String]) ?? []
        return paths.filter { $0.hasSuffix(".swift") }.sorted()
    }
}
