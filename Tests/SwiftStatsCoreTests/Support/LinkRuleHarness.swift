//
//  LinkRuleHarness.swift
//  SwiftStatsCoreTests
//
//  Tests per public function's link rules (M5) applied to a small package
//  written to a temporary directory: each directory under `Sources/` is a
//  library and each under `Tests/` a test target, named for the
//  directory. The test targets named as having run count as having run
//  every public function, so each rule is checked without an export or
//  the coverage tools.
//

@testable import SwiftStatsCore

/// Works out a small package's links.
enum LinkRuleHarness {
    /// The linked tests of each public function of the package holding
    /// `files` that isn't a witness, by key, when the test targets `ran`
    /// ran every public function and the coverage run skipped the tests
    /// `skipPatterns` match.
    static func counts(_ files: [String: String], skipPatterns: [String], ran: [String]) throws -> [String: Int] {
        let package = try TemporaryPackage(files, targets: targets(of: files))
        defer { package.remove() }
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        let measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
        let links = CoverageTestLinks(measured: measured, containers: [], skipPatterns: skipPatterns)
        var counts: [String: Int] = [:]
        for record in measured.records {
            guard let link = links.link(of: record),
                  let count = links.linkedTests(of: record, link: link, targets: ran) else {
                continue
            }
            counts[record.key] = count
        }
        return counts
    }

    /// The linked tests of each public function of the package holding
    /// `files`, as `counts(_:skipPatterns:ran:)` gives them when `LibTests`
    /// ran and the run skipped the tests `skipPatterns` match.
    static func counts(_ files: [String: String], skipPatterns: [String]) throws -> [String: Int] {
        try counts(files, skipPatterns: skipPatterns, ran: ["LibTests"])
    }

    /// The linked tests of each public function of the package holding
    /// `files`, as `counts(_:skipPatterns:ran:)` gives them when `LibTests`
    /// ran and the run skipped nothing.
    static func counts(_ files: [String: String]) throws -> [String: Int] {
        try counts(files, skipPatterns: [], ran: ["LibTests"])
    }

    /// The targets of a package holding `files`: a library for each
    /// directory under `Sources/`, a test target for each under `Tests/`.
    private static func targets(of files: [String: String]) -> [DescribedTarget] {
        var sources: [String: [String]] = [:]
        for path in files.keys where path.hasSuffix(".swift") {
            let components = path.split(separator: "/").map(String.init)
            if let file = components.last {
                sources[components.dropLast().joined(separator: "/"), default: []].append(file)
            }
        }
        return sources.sorted { $0.key < $1.key }.map { directory, files in
            DescribedTarget(
                name: directory.split(separator: "/").last.map(String.init) ?? directory,
                type: directory.hasPrefix("Tests/") ? "test" : "library",
                moduleType: "SwiftTarget",
                path: directory,
                sources: files.sorted()
            )
        }
    }
}
