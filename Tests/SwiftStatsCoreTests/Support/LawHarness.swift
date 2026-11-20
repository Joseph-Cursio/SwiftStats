//
//  LawHarness.swift
//  SwiftStatsCoreTests
//
//  Scans the Laws fixture with a fixed description (libraries `Core` and
//  `Extras`, test target `CoreTests`), so the tests need neither SwiftPM
//  nor installed tools, and runs law detection on source text.
//

import Foundation
import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax

/// Scans the Laws fixture and collects law facts from source text.
enum LawHarness {
    /// The fixture package.
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Laws")

    /// The fixture's targets: name, SwiftPM type and directory.
    private static let targets = [
        ("Core", "library", "Sources/Core"),
        ("Extras", "library", "Sources/Extras"),
        ("CoreTests", "test", "Tests/CoreTests")
    ]

    /// The fixture's description, with `dependencies` declared.
    static func package(dependencies: [DescribedDependency]) -> DescribedPackage {
        let described = targets.map { name, type, path in
            DescribedTarget(name: name, type: type, moduleType: "SwiftTarget", path: path, sources: sources(in: path))
        }
        return DescribedPackage(name: "Laws", targets: described, dependencies: dependencies)
    }

    /// The fixture scanned with no tools and no dependencies declared.
    static func scan() throws -> ScanReport {
        try scan(dependencies: [])
    }

    /// The fixture scanned with no tools, with `dependencies` declared.
    static func scan(dependencies: [DescribedDependency]) throws -> ScanReport {
        let describer = FixedDescriber(package: package(dependencies: dependencies))
        return try PackageScanner(describer: describer, tools: SnapshotHarness.noTools).scan(packageAt: fixture)
    }

    /// The law facts of every fixture file, in the order the scan walks them.
    static func fixtureFacts() throws -> [LawFileFacts] {
        try targets.flatMap { name, type, path in
            try sources(in: path).map { source -> LawFileFacts in
                let file = path + "/" + source
                let text = try String(contentsOf: fixture.appendingPathComponent(file), encoding: .utf8)
                return facts(text, file: file, module: name, isTest: type == "test")
            }
        }
    }

    /// The law facts of `source`, walked as `file` of `module`.
    static func facts(_ source: String, file: String, module: String, isTest: Bool) -> LawFileFacts {
        let tree = Parser.parse(source: source)
        return LawSyntaxCollector.collect(tree, context: FileContext(
            module: module,
            file: file,
            isTestTarget: isTest,
            testCaseClasses: [],
            converter: SourceLocationConverter(fileName: file, tree: tree),
            firstLineColumnOffset: 0
        ))
    }

    /// The Swift files under the fixture's `path`, relative to it, sorted.
    private static func sources(in path: String) -> [String] {
        let directory = fixture.appendingPathComponent(path)
        let enumerator = FileManager.default.enumerator(atPath: directory.path)
        let files = (enumerator?.allObjects as? [String]) ?? []
        return files.filter { $0.hasSuffix(".swift") }.sorted()
    }
}
