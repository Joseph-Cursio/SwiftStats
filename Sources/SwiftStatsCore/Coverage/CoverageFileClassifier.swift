//
//  CoverageFileClassifier.swift
//  SwiftStatsCore
//
//  Sorts the export's files (M5), whose paths are real paths, against the
//  package root in every spelling, first match wins: under the coverage
//  build directory is a build product; outside the root is dropped; any
//  other path is sorted by its root-relative path (`PackageFileClassifier`:
//  `.build/`, test, other-language, kept, unmapped and other-package
//  files).
//

import Foundation

/// Sorts export files for the coverage mapping.
struct CoverageFileClassifier {
    /// The package root's spellings, longest first.
    private let rootSpellings: [String]
    /// The coverage build directory's spellings, longest first.
    private let buildSpellings: [String]
    /// Sorts the root-relative paths.
    private let package: PackageFileClassifier

    /// A classifier for the package at `root`, whose coverage builds in
    /// `build` (relative to the root), with `targets`, the `parsed` files
    /// and the `excluded` globs.
    init(root: URL, build: String, targets: [TargetSummary], parsed: Set<String>, excluded: [GlobPattern]) {
        rootSpellings = Self.spellings(of: root)
        // From the root's spellings, so a build directory not made yet, or
        // reached through a symlinked root, is still recognised.
        buildSpellings = rootSpellings.map { $0 + "/" + build }
        package = PackageFileClassifier(targets: targets, parsed: parsed, excluded: excluded)
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
    func classify(_ filename: String) -> PackageFileClass {
        if Self.relative(filename, under: buildSpellings) != nil {
            return .build
        }
        guard let path = Self.relative(filename, under: rootSpellings) else {
            return .outsideRoot
        }
        return package.classify(path)
    }
}
