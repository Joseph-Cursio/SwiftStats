import Foundation
@testable import SwiftStatsCore

/// Packages in temporary git repositories, copied for a SwiftMutator run
/// the way the mutation collector copies them (M6, design §1.2), and what
/// the tests read back from the copy.
enum WorkCopyHarness {
    /// A Swift file of one statement.
    static let swift = "let value = 1\n"
    /// Another Swift file of one statement.
    static let changed = "let value = 2\n"

    /// The SHA-256 the scan reads for each file at `paths` (relative to `root`).
    static func scanned(_ paths: [String], in root: URL) throws -> [String: String] {
        var hashes: [String: String] = [:]
        for path in paths {
            hashes[path] = ContentHash.sha256(try Data(contentsOf: root.appendingPathComponent(path)))
        }
        return hashes
    }

    /// The copy of the package at `packageRoot`, made with its git state
    /// now, the files at `paths` scanned, and the files at `ignored` left out.
    static func copy(
        _ packageRoot: URL,
        scanning paths: [String],
        ignoring ignored: [String]
    ) throws -> (MutationDirectory, MutationWorkCopy) {
        try copy(
            packageRoot,
            git: GitReader.read(packageRoot: packageRoot, ignoring: ignored),
            scanning: paths,
            ignoring: ignored
        )
    }

    /// The copy of the package at `packageRoot`, made with the git state
    /// `git` (as a scan read it, maybe before a later commit), the files at
    /// `paths` scanned now, and the files at `ignored` left out.
    static func copy(
        _ packageRoot: URL,
        git: GitState,
        scanning paths: [String],
        ignoring ignored: [String]
    ) throws -> (MutationDirectory, MutationWorkCopy) {
        let directory = try MutationDirectory(packageRoot: packageRoot)
        let copy = try MutationWorkCopy.make(
            packageRoot: packageRoot,
            git: git,
            scanned: try scanned(paths, in: packageRoot),
            ignoring: ignored,
            in: directory
        )
        return (directory, copy)
    }

    /// Every file and link below `folder` (paths relative to it, sorted),
    /// nothing inside a `.git` folder or `.git` entry itself.
    static func entries(of folder: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: folder.path) else {
            return []
        }
        var paths: [String] = []
        while let path = enumerator.nextObject() as? String {
            let isDirectory = enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if path.split(separator: "/").last == ".git" {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }
            if isDirectory == false {
                paths.append(path)
            }
        }
        return paths.sorted()
    }

    /// The text of the file at `path` below `folder`.
    static func text(_ path: String, in folder: URL) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
    }

    /// The target of the link at `path` below `folder`, or nil when it isn't one.
    static func link(_ path: String, in folder: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: folder.appendingPathComponent(path).path)
    }

    /// `realpath(3)` of `url`, or its path when that fails.
    static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else {
            return url.path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Writes `marker` into a new folder at `url`, standing for a build.
    static func build(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
    }
}
