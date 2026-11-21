//
//  CoverageFileClassifier.swift
//  SwiftStatsCore
//
//  Sorts the export's files (M5), whose paths are real paths, against the
//  package root in every spelling, first match wins: under the coverage
//  build directory, or a root-relative path in `.build/`, is a build
//  product; outside the root is dropped; in a test target's directory is a
//  test file; any other file that isn't Swift (a C, C++ or assembly
//  target's, which SwiftPM instruments too) is another language's; in a
//  production target's directory is kept when the scan parsed it, else
//  listed as unmapped (`excluded` when the configuration excludes it, else
//  `not parsed`); anything else under the root is another package's.
//

import Foundation

/// Sorts export files for the coverage mapping.
struct CoverageFileClassifier {
    /// A target directory's place in the classification.
    private struct TargetDirectory {
        /// The directory, relative to the root, with a trailing slash;
        /// empty for the root itself.
        let prefix: String
        /// The target's name.
        let name: String
        /// Whether it holds tests.
        let isTest: Bool
    }

    /// The root-relative directory a package's own build lands in.
    private static let packageBuild = ".build/"
    /// What a path relative to the root may start with.
    private static let currentDirectory = "./"
    /// What a Swift file's name ends with.
    private static let swiftExtension = ".swift"

    /// The package root's spellings, longest first.
    private let rootSpellings: [String]
    /// The coverage build directory's spellings, longest first.
    private let buildSpellings: [String]
    /// Each target's directory, the longest first.
    private let targets: [TargetDirectory]
    /// The files the scan parsed.
    private let parsed: Set<String>
    /// The configuration's exclusion globs.
    private let excluded: [GlobPattern]

    /// A classifier for the package at `root`, whose coverage builds in
    /// `build` (relative to the root), with `targets`, the `parsed` files
    /// and the `excluded` globs.
    init(root: URL, build: String, targets: [TargetSummary], parsed: Set<String>, excluded: [GlobPattern]) {
        rootSpellings = Self.spellings(of: root)
        // From the root's spellings, so a build directory not made yet, or
        // reached through a symlinked root, is still recognised.
        buildSpellings = rootSpellings.map { $0 + "/" + build }
        self.targets = targets
            .map { TargetDirectory(prefix: Self.directory($0.path), name: $0.name, isTest: $0.isTest) }
            .sorted { ($0.prefix.count, $0.prefix) > ($1.prefix.count, $1.prefix) }
        self.parsed = parsed
        self.excluded = excluded
    }

    /// `path` as a directory prefix: a trailing slash, none for the root.
    private static func directory(_ path: String) -> String {
        let trimmed = path.hasPrefix(currentDirectory) ? String(path.dropFirst(currentDirectory.count)) : path
        if trimmed.isEmpty || trimmed == "." {
            return ""
        }
        return trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
    }

    /// `directory`'s spellings: `PathSpellings`' and its real path, longest
    /// first.
    private static func spellings(of directory: URL) -> [String] {
        var spellings = Set(PathSpellings.of(directory))
        if let resolved = realpath(directory.path, nil) {
            spellings.insert(String(cString: resolved))
            free(resolved)
        }
        return spellings.sorted { ($0.count, $0) > ($1.count, $1) }
    }

    /// `path` relative to the first of `spellings` it lies under; nil when
    /// it lies under none.
    private static func relative(_ path: String, under spellings: [String]) -> String? {
        for spelling in spellings {
            let prefix = spelling.hasSuffix("/") ? spelling : spelling + "/"
            if path.hasPrefix(prefix) {
                return String(path.dropFirst(prefix.count))
            }
        }
        return nil
    }

    /// Where the export file at `filename` belongs.
    func classify(_ filename: String) -> CoverageFileClass {
        if Self.relative(filename, under: buildSpellings) != nil {
            return .build
        }
        guard let path = Self.relative(filename, under: rootSpellings) else {
            return .outsideRoot
        }
        if path.hasPrefix(Self.packageBuild) {
            return .build
        }
        let target = targets.first { path.hasPrefix($0.prefix) }
        if target?.isTest == true {
            return .testFile
        }
        // The scan's targets are its Swift ones, and SwiftStats parses
        // only Swift: a C target's file is neither another package's nor
        // a production file left unparsed.
        if path.hasSuffix(Self.swiftExtension) == false {
            return .otherLanguage
        }
        guard let target else {
            return .otherPackage
        }
        if parsed.contains(path) {
            return .kept(path: path, module: target.name)
        }
        let isExcluded = excluded.contains { $0.matches(path) }
        return .unmapped(path: path, module: target.name, reason: isExcluded ? "excluded" : "not parsed")
    }
}
