//
//  MutationChanges.swift
//  SwiftStatsCore
//
//  What SwiftStats reads in the copy for a `--since` merge (M6, design
//  §6.1). First SwiftMutator's own selection, worked out with its own git
//  command in the copy, which is the scanned tree: the Swift files the
//  working tree changed against the base's commit (committed, uncommitted
//  and untracked, a rename by its new path, deletions dropped). A run that
//  wrote no results file tested nothing, yet its selection's production
//  files have changed, so their results can't be carried; the selection's
//  test files are the ones carried verdicts weren't retested against.
//  Then, for a run that wrote no results file, the tree itself: every
//  Swift file of the copy SwiftMutator lists, hashed as SwiftMutator
//  hashes it, since there is no header to take it from. Before the run, in
//  the package itself, the manifests that differ from the base's commit
//  (deletions included), which refuse the merge.
//

import Foundation

/// The files a `--since` run's copy changed, and its tree when the run
/// left no header to read it from.
struct MutationChanges: Hashable, Sendable {
    /// What a Swift file's name ends with.
    private static let swiftSuffix = ".swift"
    /// The status git gives a deleted path.
    private static let deletedStatus = "D"
    /// The statuses whose entry names two paths, the old and the new.
    private static let twoPathStatuses: Set<Character> = ["C", "R"]
    /// How many paths such an entry names.
    private static let twoPaths = 2
    /// The package manifest's name.
    private static let manifest = "Package.swift"
    /// What a versioned manifest's name starts with.
    private static let versionedManifestPrefix = "Package@swift-"

    /// The Swift paths changed since the base's commit, relative to the
    /// project, as SwiftMutator's own selection lists them, sorted.
    let selection: [String]
    /// The hash of each Swift path of the copy, as SwiftMutator hashes it,
    /// when the run left no results file; empty when it left one, whose
    /// header's tree is the merge's.
    let tree: [String: String]

    /// The Swift files of `project`, the copy, changed since `commit`, as
    /// SwiftMutator selects them: `git diff --name-status -z --relative
    /// --find-renames --ignore-submodules=all <commit> --` and the
    /// untracked files git doesn't ignore, Swift files only, a rename by
    /// its new path, deletions dropped.
    static func read(in project: URL, since commit: String) throws(MutationFailure) -> Self {
        let diff = try git(
            ["diff", "--name-status", "-z", "--relative", "--find-renames", "--ignore-submodules=all", commit, "--"],
            in: project
        )
        let untracked = try git(["ls-files", "--others", "--exclude-standard", "-z"], in: project)
        let paths = changedPaths(diff) + untracked
        return Self(selection: Set(paths.filter { $0.hasSuffix(swiftSuffix) }).sorted(), tree: [:])
    }

    /// The manifests at the top of `project`, the package (`Package.swift`
    /// and `Package@swift-*.swift`), that differ in its working tree from
    /// `commit`: changed, added, deleted, or untracked and not ignored,
    /// sorted.
    static func manifests(in project: URL, since commit: String) throws(MutationFailure) -> [String] {
        let diff = try git(
            ["diff", "--name-only", "-z", "--relative", "--no-renames", "--ignore-submodules=all", commit, "--"],
            in: project
        )
        let untracked = try git(["ls-files", "--others", "--exclude-standard", "-z"], in: project)
        return Set((diff + untracked).filter(isManifest)).sorted()
    }

    /// Whether `path`, relative to the package, is one of its manifests.
    static func isManifest(_ path: String) -> Bool {
        path == manifest
            || (path.hasPrefix(versionedManifestPrefix) && path.hasSuffix(swiftSuffix) && path.contains("/") == false)
    }

    /// The paths `entries`, a `--name-status -z` listing, names: each
    /// entry's path, the new one of a rename or copy, deletions dropped.
    static func changedPaths(_ entries: [String]) -> [String] {
        var paths: [String] = []
        var index = entries.startIndex
        while index < entries.endIndex {
            let status = entries[index]
            let count = status.first.map { twoPathStatuses.contains($0) } == true ? twoPaths : 1
            let end = min(index + 1 + count, entries.endIndex)
            if status != deletedStatus, let last = entries[(index + 1)..<end].last {
                paths.append(last)
            }
            index = end
        }
        return paths
    }

    /// The hash of every Swift file of `project` SwiftMutator lists (never
    /// in a build folder or a nested checkout), by its path from
    /// `project`: its bytes' SHA-256, or `link:` and the SHA-256 of the
    /// path a symbolic link points to.
    static func tree(of project: URL) throws(MutationFailure) -> [String: String] {
        var hashes: [String: String] = [:]
        do {
            try MutationProjectFiles.walk(project, excluding: [], skippingCheckouts: true) { path, isDirectory in
                guard isDirectory == false, path.hasSuffix(swiftSuffix) else {
                    return
                }
                let file = project.appendingPathComponent(path)
                if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: file.path) {
                    hashes[path] = MutationTree.linkPrefix + ContentHash.sha256(Data(target.utf8))
                } else if let hash = ContentHash.sha256(ofFileAt: file) {
                    hashes[path] = hash
                }
            }
        } catch {
            throw MutationWorkCopy.failure("hash the copy's Swift files", error)
        }
        return hashes
    }

    /// The NUL-separated paths `git <arguments>` prints in `project`, run
    /// without the variables that name a repository, so it reads the
    /// copy's own; a failure naming the subcommand.
    private static func git(_ arguments: [String], in project: URL) throws(MutationFailure) -> [String] {
        let data: Data
        do {
            data = try ProcessRunner.run(
                executable: GitReader.git,
                arguments: ["--no-optional-locks"] + arguments,
                in: project,
                environment: [:],
                removing: MutationWorkCopy.repositoryVariables
            )
        } catch {
            var reason = "could not list the files changed since the base: git \(arguments[0])"
            if case let .commandFailed(_, status, _) = error as? ScanError {
                reason += " exited \(status)"
            }
            throw MutationFailure(description: reason)
        }
        return try MutationWorkCopy.decodedPaths(data)
    }

    /// The changes, with the copy's tree `files`.
    func with(tree files: [String: String]) -> Self {
        Self(selection: selection, tree: files)
    }
}
