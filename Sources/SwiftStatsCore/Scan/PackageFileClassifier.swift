//
//  PackageFileClassifier.swift
//  SwiftStatsCore
//
//  Sorts files a tool names by their paths relative to the package root
//  (M5, M6), first match wins: in the root's `.build/` is a build product;
//  an absolute path, or one leaving the root through `..`, is outside the
//  root; in a test target's directory is a test file; any other file that
//  isn't Swift (a C, C++ or assembly target's, which SwiftPM instruments
//  too) is another language's; in a production target's directory is kept
//  when the scan parsed it, else listed as unmapped (`excluded` when the
//  configuration excludes it, else `not parsed`); anything else is another
//  package's. Coverage first sorts out the export's absolute paths outside
//  the root and in its build directory (`CoverageFileClassifier`).
//

/// Sorts package-relative paths for the coverage and mutation mappings.
struct PackageFileClassifier {
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
    /// The parent directory, which a path leaving the root starts with.
    private static let parentDirectory = ".."
    /// What a Swift file's name ends with.
    private static let swiftExtension = ".swift"

    /// Each target's directory, the longest first.
    private let targets: [TargetDirectory]
    /// The files the scan parsed.
    private let parsed: Set<String>
    /// The configuration's exclusion globs.
    private let excluded: [GlobPattern]

    /// A classifier for a package with `targets`, the `parsed` files and
    /// the `excluded` globs.
    init(targets: [TargetSummary], parsed: Set<String>, excluded: [GlobPattern]) {
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

    /// Whether `path` names no place under the root: absolute, or leaving
    /// it through `..`.
    private static func leavesRoot(_ path: String) -> Bool {
        path.hasPrefix("/") || path == parentDirectory || path.hasPrefix(parentDirectory + "/")
    }

    /// Where the file at `path`, relative to the package root, belongs.
    func classify(_ path: String) -> PackageFileClass {
        if path.hasPrefix(Self.packageBuild) {
            return .build
        }
        if Self.leavesRoot(path) {
            return .outsideRoot
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
