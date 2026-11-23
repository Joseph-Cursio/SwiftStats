//
//  MutationProjectFiles.swift
//  SwiftStatsCore
//
//  Which of a package's files SwiftMutator lists (M6, design §1.2), as its
//  `ProjectTree` does at b16642de: git's files, plus every Swift file and
//  `.swift-version` at any depth and the `Package.resolved` at the root or
//  in a workspace's `xcshareddata/swiftpm/` even when git ignores them,
//  never inside `.build`, `.git`, `.swiftpm`, `DerivedData` or
//  `xcuserdata`, and, with git, never by this walk inside a nested
//  checkout (a folder holding a `.git` entry): SwiftMutator takes a
//  submodule's or an untracked nested repository's files from that
//  checkout's own listing, and leaves an ignored one out. The copy
//  SwiftMutator runs in takes the ignored files from the package, so it
//  lists in the copy what it would list in the package, nested checkouts
//  aside (a known limit, `MutationWorkCopy+Git`).
//

import Foundation

/// SwiftMutator's listing rules, and a walk that applies them.
enum MutationProjectFiles {
    /// The names SwiftMutator never lists at any depth, nor anything in a
    /// folder of one of them.
    static let prunedNames: Set<String> = [".build", ".git", ".swiftpm", "DerivedData", "xcuserdata"]
    /// The toolchain pin swiftly reads.
    static let toolchainPin = ".swift-version"
    /// The resolved dependency versions, listed only at the root and in a
    /// workspace's shared SwiftPM folder.
    private static let resolvedFile = "Package.resolved"
    /// What a workspace's folder name ends with; an Xcode project's own
    /// workspace is `project.xcworkspace` inside it, so it counts too.
    private static let workspaceSuffix = ".xcworkspace"
    /// The folders between a workspace and its `Package.resolved`.
    private static let workspaceResolvedFolders = ["xcshareddata", "swiftpm"]
    /// What a Swift file's name ends with.
    private static let swiftSuffix = ".swift"
    /// A checkout's git entry: a folder, or a file naming one.
    private static let gitEntry = ".git"

    /// Whether SwiftMutator lists `path` (relative to the project) even
    /// when git ignores it: a Swift file or `.swift-version` at any depth,
    /// or `Package.resolved` at the root or in
    /// `*.xcworkspace/xcshareddata/swiftpm/`.
    static func isAlwaysListed(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last else {
            return false
        }
        if name.hasSuffix(swiftSuffix) || name == toolchainPin {
            return true
        }
        guard name == resolvedFile else {
            return false
        }
        let folders = components.dropLast()
        guard folders.isEmpty == false else {
            return true
        }
        let workspace = folders.dropLast(workspaceResolvedFolders.count)
        return folders.suffix(workspaceResolvedFolders.count).elementsEqual(workspaceResolvedFolders)
            && workspace.last?.hasSuffix(workspaceSuffix) == true
    }

    /// Calls `visit` with the path (relative to `root`) and whether it is
    /// a directory itself, for everything below `root` in sorted order,
    /// never following a link. It visits nothing of a pruned name, nothing at
    /// `excluded` (paths relative to `root`), and, when
    /// `skippingCheckouts`, no folder below `root` holding a `.git` entry;
    /// those are not visited either.
    static func walk(
        _ root: URL,
        excluding excluded: Set<String>,
        skippingCheckouts: Bool,
        visit: (String, Bool) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let names = try fileManager.contentsOfDirectory(atPath: root.path).sorted()
        for name in names {
            try walk(root, path: name, excluding: excluded, skippingCheckouts: skippingCheckouts, visit: visit)
        }
    }

    /// `walk` from the entry at `path` (relative to `root`) down.
    private static func walk(
        _ root: URL,
        path: String,
        excluding excluded: Set<String>,
        skippingCheckouts: Bool,
        visit: (String, Bool) throws -> Void
    ) throws {
        let url = root.appendingPathComponent(path)
        guard excluded.contains(path) == false, prunedNames.contains(url.lastPathComponent) == false else {
            return
        }
        guard FileClone.isDirectory(url) else {
            try visit(path, false)
            return
        }
        if skippingCheckouts, FileClone.exists(url.appendingPathComponent(gitEntry)) {
            return
        }
        try visit(path, true)
        for name in try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() {
            try walk(
                root,
                path: path + "/" + name,
                excluding: excluded,
                skippingCheckouts: skippingCheckouts,
                visit: visit
            )
        }
    }
}
