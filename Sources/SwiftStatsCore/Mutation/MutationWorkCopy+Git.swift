//
//  MutationWorkCopy+Git.swift
//  SwiftStatsCore
//
//  How the mutation collector's copy is filled (M6, design §1.2 steps 1–3
//  and 6). With git: a shared clone without a checkout, so it reads the
//  source's objects through `objects/info/alternates` and copies none; a
//  cone-mode sparse checkout of the package's path when the package is
//  below the top level (cone mode also checks out the files directly in
//  each folder above it, so a `.swift-version` above the package comes
//  too); a detached checkout of the commit the scan read, with no hook
//  run, no LFS download (a pointer git leaves in place of a parsed file is
//  fixed by the hash check) and none of the variables that name a
//  repository, so no command can write into the source's. Then the
//  overlay, as byte copies from the package with links kept as links: the
//  package's changes against that commit, listed with the options and
//  pathspecs `GitReader` hashes them with, deleted files removed first,
//  none in a folder SwiftMutator never lists; the files SwiftMutator lists
//  even when git ignores them that the copy doesn't have; and each
//  `.swift-version` above the package as the work tree holds it. Outside
//  git, the package is copied whole, but for SwiftStats' own folder, the
//  files at `ignored` and every folder SwiftMutator never lists.
//
//  A submodule, or an untracked nested repository, is left out of the
//  copy (a known limit), though SwiftMutator lists its files in the
//  package from that checkout's own listing; a scanned file in one still
//  reaches the copy through the hash check.
//

import Foundation

extension MutationWorkCopy {
    /// The variables that name a repository, as `git rev-parse
    /// --local-env-vars` lists them: the commands that write the copy run
    /// without them, so one a hook or a shell exported can't point them at
    /// the source's repository (SwiftMutator's own git runs without them).
    static let repositoryVariables: Set<String> = [
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
        "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE",
        "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX", "GIT_SHALLOW_FILE",
        "GIT_COMMON_DIR"
    ]
    /// Environment for the git commands that check out the copy: LFS
    /// leaves its pointers rather than downloading anything.
    private static let checkoutEnvironment = ["GIT_LFS_SKIP_SMUDGE": "1"]
    /// Options for those commands: no hook runs in the copy.
    private static let noHooks = ["-c", "core.hooksPath=/dev/null"]

    /// Clones the repository at `top` into `clone`, sparse to
    /// `packagePath` when it isn't empty, and checks out `commit`.
    static func checkOut(_ commit: String, of top: URL, packagePath: String, into clone: URL) throws(MutationFailure) {
        let work = clone.deletingLastPathComponent()
        let redactions = [(work, "<copy>"), (top, "<repository>")]
        try git(
            "clone",
            ["clone", "--quiet", "--shared", "--no-checkout", top.path, clone.path],
            in: work,
            redacting: redactions,
            isolated: true
        )
        if packagePath.isEmpty == false {
            try git(
                "sparse-checkout",
                noHooks + ["sparse-checkout", "set", "--cone", "--end-of-options", packagePath],
                in: clone,
                redacting: redactions,
                isolated: true
            )
        }
        try git(
            "checkout",
            noHooks + ["checkout", "--quiet", "--detach", commit],
            in: clone,
            redacting: redactions,
            isolated: true
        )
    }

    /// Lays over `project`, the package's folder in a checkout of
    /// `commit`, the package at `packageRoot`'s changes against `commit`
    /// (the commit the scan read, which HEAD may have left since), and the
    /// files SwiftMutator lists though git ignores them.
    static func overlay(
        _ packageRoot: URL,
        against commit: String,
        ignoring ignored: [String],
        onto project: URL
    ) throws(MutationFailure) {
        let pathspecs = GitReader.pathspecs(ignoring: ignored)
        let diff = ["--no-optional-locks", "-c", "core.quotepath=off", "diff", commit]
            + ["--name-only", "-z", "--relative"] + GitReader.plainDiff
        let deleted = try paths("diff", diff + ["--diff-filter=D"] + pathspecs, in: packageRoot)
        let changed = try paths("diff", diff + ["--diff-filter=d"] + pathspecs, in: packageRoot)
        let untracked = try paths(
            "ls-files",
            ["ls-files", "-z", "--others", "--exclude-standard"] + pathspecs,
            in: packageRoot
        )
        // Deletions first, as git lists them rather than by a lookup: on a
        // case-insensitive volume a case-only rename's old name finds the
        // new file, and a file replaced by a folder must go before the
        // folder's files come.
        for path in deleted.sorted() {
            try attempt(path) {
                try FileClone.remove(project.appendingPathComponent(path))
            }
        }
        for path in Set(changed + untracked).sorted() where isLeftOut(path, in: packageRoot) == false {
            let source = packageRoot.appendingPathComponent(path)
            let destination = project.appendingPathComponent(path)
            try attempt(path) {
                if FileClone.exists(source) {
                    try FileClone.copy(source, to: destination)
                } else {
                    try FileClone.remove(destination)
                }
            }
        }
        try copyListed(packageRoot, ignoring: ignored, to: project)
    }

    /// Makes each `.swift-version` directly in a folder above the package
    /// in `clone` (the checkout of the repository at `top`, holding the
    /// package at `packagePath`) the one the work tree holds there, or
    /// removes it when the work tree holds none: cone mode checks out the
    /// committed one, and swiftly reads the first it finds walking up from
    /// the copy's project.
    static func overlayPins(of top: URL, packagePath: String, into clone: URL) throws(MutationFailure) {
        let folders = packagePath.split(separator: "/").map(String.init)
        for depth in folders.indices {
            let path = (folders.prefix(depth) + [MutationProjectFiles.toolchainPin]).joined(separator: "/")
            let source = top.appendingPathComponent(path)
            let destination = clone.appendingPathComponent(path)
            try attempt(path) {
                if FileClone.exists(source) {
                    try FileClone.copy(source, to: destination)
                } else {
                    try FileClone.remove(destination)
                }
            }
        }
    }

    /// Copies the package at `packageRoot` to `project`, which doesn't
    /// exist, but for SwiftStats' folder, `ignored` and the folders
    /// SwiftMutator never lists.
    static func copyPackage(_ packageRoot: URL, ignoring ignored: [String], to project: URL) throws(MutationFailure) {
        try attempt(".") {
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try MutationProjectFiles.walk(
                packageRoot,
                excluding: excluded(ignored),
                skippingCheckouts: false
            ) { path, isDirectory in
                let destination = project.appendingPathComponent(path)
                if isDirectory {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                } else {
                    try FileClone.copy(packageRoot.appendingPathComponent(path), to: destination)
                }
            }
        }
    }

    /// The NUL-separated paths in `data`, as git prints them with `-z`; a
    /// failure when any name isn't UTF-8, rather than leaving that file out
    /// of the copy unsaid.
    static func decodedPaths(_ data: Data) throws(MutationFailure) -> [String] {
        let names = data.split(separator: 0)
        let paths = names.compactMap { String(bytes: $0, encoding: .utf8) }
        guard paths.count == names.count else {
            throw MutationFailure(
                description: "making the copy failed: git lists paths that aren't UTF-8: "
                    + "\(names.count - paths.count) of \(names.count)"
            )
        }
        return paths
    }

    /// Whether the overlay leaves out the changed path `path` of the
    /// package at `packageRoot`: a folder, which is a submodule's or an
    /// untracked nested repository's (git lists either as one path), or a
    /// path in a folder SwiftMutator never lists, such as a build folder
    /// git doesn't ignore, which build-cache replaces.
    private static func isLeftOut(_ path: String, in packageRoot: URL) -> Bool {
        FileClone.isDirectory(packageRoot.appendingPathComponent(path))
            || path.split(separator: "/").contains { MutationProjectFiles.prunedNames.contains(String($0)) }
    }

    /// Copies each file below `packageRoot` that SwiftMutator lists even
    /// when git ignores it, and that `project` lacks.
    private static func copyListed(
        _ packageRoot: URL,
        ignoring ignored: [String],
        to project: URL
    ) throws(MutationFailure) {
        try attempt(".") {
            try MutationProjectFiles.walk(
                packageRoot,
                excluding: excluded(ignored),
                skippingCheckouts: true
            ) { path, isDirectory in
                let destination = project.appendingPathComponent(path)
                guard isDirectory == false, MutationProjectFiles.isAlwaysListed(path),
                      FileClone.exists(destination) == false else {
                    return
                }
                try FileClone.copy(packageRoot.appendingPathComponent(path), to: destination)
            }
        }
    }

    /// The paths the copy never takes from the package: SwiftStats' own
    /// folder, and the files at `ignored` with SQLite's companions.
    private static func excluded(_ ignored: [String]) -> Set<String> {
        Set([StoreLocation.directoryName] + GitReader.companions(of: ignored))
    }

    /// The NUL-separated paths `git <arguments>` (its `subcommand`) prints
    /// in the package at `packageRoot`.
    private static func paths(
        _ subcommand: String,
        _ arguments: [String],
        in packageRoot: URL
    ) throws(MutationFailure) -> [String] {
        let data = try git(
            subcommand,
            arguments,
            in: packageRoot,
            redacting: [(packageRoot, "<package>")],
            isolated: false
        )
        return try decodedPaths(data)
    }

    /// What `git <arguments>` prints in `directory`, without the variables
    /// that name a repository when `isolated` (a command that writes the
    /// copy; one that reads the package runs as `GitReader`'s do); a
    /// failure names the `subcommand`, its exit status and its cleaned
    /// error, each directory in `redactions` replaced by its placeholder.
    @discardableResult
    private static func git(
        _ subcommand: String,
        _ arguments: [String],
        in directory: URL,
        redacting redactions: [(URL, String)],
        isolated: Bool
    ) throws(MutationFailure) -> Data {
        do {
            return try ProcessRunner.run(
                executable: GitReader.git,
                arguments: arguments,
                in: directory,
                environment: checkoutEnvironment,
                removing: isolated ? repositoryVariables : []
            )
        } catch {
            var reason = "making the copy failed: git \(subcommand)"
            if case let .commandFailed(_, status, text) = error as? ScanError {
                let cleaned = CoverageStderr.cleaned(text, replacing: redactions)
                reason += " exited \(status)" + (cleaned.isEmpty ? "" : ": \(cleaned)")
            }
            throw MutationFailure(description: reason)
        }
    }

    /// Runs `body`, a file operation on `path` (relative to the package,
    /// or to the repository for a pin above it), turning its error into a
    /// failure naming the path.
    private static func attempt(_ path: String, _ body: () throws -> Void) throws(MutationFailure) {
        do {
            try body()
        } catch {
            throw failure("copy \(path) into the copy", error)
        }
    }
}
