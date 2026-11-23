//
//  MutationDirectory.swift
//  SwiftStatsCore
//
//  Where the SwiftMutator collector keeps its files (M6, design §1.2):
//  `.swiftstats/mutation/` in the package, which `.swiftstats/`'s own
//  `.gitignore` of `*` keeps out of `git status`, whatever the store
//  setting. `work/` holds the temporary copy SwiftMutator runs in and
//  exists only while a run is under way, or after an interrupted one;
//  `build-cache/` holds the package's `.build` between runs, renamed into
//  and out of the copy, which the same volume makes cheap.
//

import Foundation

/// The mutation collector's folder in a package, and its parts.
struct MutationDirectory: Sendable {
    /// The folder's name inside `.swiftstats/`.
    static let name = "mutation"
    /// The temporary copy's folder's name.
    static let workName = "work"
    /// The kept build's folder's name.
    static let buildCacheName = "build-cache"

    /// `.swiftstats/mutation/` in the package.
    let root: URL

    /// The folder the temporary copy is made in.
    var work: URL {
        root.appendingPathComponent(Self.workName)
    }

    /// The package's `.build` between runs.
    var buildCache: URL {
        root.appendingPathComponent(Self.buildCacheName)
    }

    /// The folder of the package at `packageRoot`, made, with
    /// `.swiftstats/` and its `.gitignore`, when missing.
    init(packageRoot: URL) throws {
        root = try StoreLocation.ignoreDirectory(packageRoot: packageRoot).appendingPathComponent(Self.name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}
