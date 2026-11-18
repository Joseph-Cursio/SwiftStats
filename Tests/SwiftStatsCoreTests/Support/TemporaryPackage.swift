import Foundation
@testable import SwiftStatsCore

/// A package written to a temporary directory and scanned with a fixed
/// description, so tests need neither SwiftPM nor installed tools.
struct TemporaryPackage {
    /// A describer that returns the same description for any path.
    private struct FixedDescriber: PackageDescriber {
        let package: DescribedPackage

        func describePackage(at _: URL) -> DescribedPackage {
            package
        }
    }

    /// The package root.
    let root: URL
    /// The targets the description lists.
    let targets: [DescribedTarget]

    /// A package holding `files` (paths relative to the root) and a
    /// `Package.swift`, whose description lists a library `Lib` with the
    /// files under `Sources/Lib/` and a test target `LibTests` with those
    /// under `Tests/LibTests/`.
    init(_ files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryPackage-\(UUID().uuidString)")
        for (path, contents) in files.merging(["Package.swift": ""], uniquingKeysWith: { first, _ in first }) {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        let sources = { (prefix: String) in
            files.keys.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".swift") }
                .map { String($0.dropFirst(prefix.count)) }
                .sorted()
        }
        targets = [
            DescribedTarget(
                name: "Lib",
                type: "library",
                moduleType: "SwiftTarget",
                path: "Sources/Lib",
                sources: sources("Sources/Lib/")
            ),
            DescribedTarget(
                name: "LibTests",
                type: "test",
                moduleType: "SwiftTarget",
                path: "Tests/LibTests",
                sources: sources("Tests/LibTests/")
            )
        ].filter { $0.sources.isEmpty == false }
    }

    /// Scans the package, finding tools with `tools`.
    func scan(tools: ToolLocator) throws -> ScanReport {
        let describer = FixedDescriber(package: DescribedPackage(name: "Probe", targets: targets))
        return try PackageScanner(describer: describer, tools: tools).scan(packageAt: root)
    }

    /// Removes the package.
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
