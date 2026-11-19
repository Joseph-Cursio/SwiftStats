//
//  GitReader.swift
//  SwiftStatsCore
//
//  Reads a package's git state with read-only git (PRD §6.2): no command
//  takes git's optional locks, so a scan never writes into `.git`.
//

import CryptoKit
import Foundation

/// Reads commit, branch and dirtiness for a package directory.
enum GitReader {
    /// The git executable.
    static let git = "/usr/bin/git"
    /// Pathspecs for the package directory without SwiftStats' own store.
    private static let packagePathspecs = ["--", ".", ":(exclude).swiftstats"]
    /// Options that make `git diff`'s output depend on the trees alone, not
    /// on the user's diff configuration (external tools, text conversion,
    /// prefixes, rename detection, colour).
    private static let plainDiff = [
        "--binary", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames", "--full-index",
        "--src-prefix=a/", "--dst-prefix=b/"
    ]
    /// Suffixes of the files SQLite keeps beside a database.
    private static let databaseCompanions = ["", "-journal", "-wal", "-shm"]

    /// The state of the package at `root`; `GitState.outsideGit` outside git.
    static func read(packageRoot root: URL) -> GitState {
        read(packageRoot: root, ignoring: [])
    }

    /// The state of the package at `root`, its changes not counting the
    /// files at `ignored` (paths relative to `root`, such as a store kept in
    /// the package) or SQLite's companions of them.
    static func read(packageRoot root: URL, ignoring ignored: [String]) -> GitState {
        guard line(["rev-parse", "--show-toplevel"], in: root) != nil else {
            return .outsideGit
        }
        let prefix = line(["rev-parse", "--show-prefix"], in: root) ?? ""
        let packagePath = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        guard let commit = line(["rev-parse", "--verify", "--quiet", "HEAD"], in: root) else {
            // A repository with no commits: nothing to name the state by.
            return GitState(commit: nil, branch: nil, isDirty: false, dirtyHash: nil, packagePath: packagePath)
        }
        let branch = line(["symbolic-ref", "--short", "--quiet", "HEAD"], in: root)
        let excluded = ignored.flatMap { path in databaseCompanions.map { ":(exclude)\(path)\($0)" } }
        let dirtyHash = changesHash(in: root, pathspecs: packagePathspecs + excluded)
        return GitState(
            commit: commit,
            branch: branch,
            isDirty: dirtyHash != nil,
            dirtyHash: dirtyHash,
            packagePath: packagePath
        )
    }

    /// Whether the directory at `root` is the top level of a git work tree.
    static func isTopLevel(_ root: URL) -> Bool {
        guard let top = line(["rev-parse", "--show-toplevel"], in: root) else {
            return false
        }
        return URL(fileURLWithPath: top).resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path
    }

    /// Whether the work tree at `root` has any change against HEAD.
    static func isClean(_ root: URL) -> Bool {
        guard let status = output(["--no-optional-locks", "status", "--porcelain"], in: root) else {
            return false
        }
        return status.isEmpty
    }

    /// The first line `git <arguments>` prints in `directory`, or nil when
    /// it fails or prints nothing.
    static func line(_ arguments: [String], in directory: URL) -> String? {
        guard let data = output(arguments, in: directory),
              let text = String(data: data, encoding: .utf8),
              let first = text.split(whereSeparator: \.isNewline).first else {
            return nil
        }
        return String(first)
    }

    /// What `git <arguments>` prints in `directory`, or nil when it fails.
    static func output(_ arguments: [String], in directory: URL) -> Data? {
        try? ProcessRunner.run(executable: git, arguments: arguments, in: directory)
    }

    /// A hash of the package directory's changes against HEAD: the binary
    /// diff of tracked files, staged or not, then each untracked file that
    /// isn't ignored, by path and content (a symlink by its target). Nil
    /// when there are none.
    private static func changesHash(in root: URL, pathspecs: [String]) -> String? {
        let command = ["--no-optional-locks", "-c", "core.quotepath=off", "diff", "HEAD"] + plainDiff + pathspecs
        let diff = output(command, in: root) ?? Data()
        let untracked = output(["ls-files", "-z", "--others", "--exclude-standard"] + pathspecs, in: root)
            .map { data in
                data.split(separator: 0).compactMap { String(bytes: $0, encoding: .utf8) }.sorted()
            } ?? []
        guard diff.isEmpty == false || untracked.isEmpty == false else {
            return nil
        }
        var hasher = SHA256()
        hasher.update(data: diff)
        for path in untracked {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            let file = root.appendingPathComponent(path)
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: file.path) {
                hasher.update(data: Data(target.utf8))
            } else if let contents = try? Data(contentsOf: file) {
                hasher.update(data: contents)
            }
            hasher.update(data: Data([0]))
        }
        return ContentHash.hex(hasher.finalize())
    }
}
