//
//  UnbuiltTests.swift
//  SwiftStatsCore
//
//  Generated tests left in the legacy `Tests/Generated/` folder are in no
//  test target, so they are never built or run (PRD §7.8). Each is reported.
//

import Foundation

/// Finds Swift files under `Tests/Generated/` that no target compiles.
enum UnbuiltTests {
    /// The legacy folder, relative to the package root.
    static let folder = "Tests/Generated"

    /// A warning for each Swift file under `root/Tests/Generated/` missing from `compiled`.
    static func warnings(root: URL, compiled: Set<String>) -> [ScanWarning] {
        let directory = root.appendingPathComponent(folder)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { RelativePath.of($0.path, under: root) }
            .filter { compiled.contains($0) == false }
            .sorted()
            .map { ScanWarning(file: $0, message: "in \(folder)/ but in no target, so never built or run") }
    }
}
