//
//  MutationTree.swift
//  SwiftStatsCore
//
//  A SwiftMutator session's project tree (M6, design §2 items 4 and 10):
//  every file it listed, by path relative to the project, with the SHA-256
//  of its raw bytes, or, for a symbolic link, `link:` and the SHA-256 of
//  the path it points to. A resumed session records only what changed
//  since an earlier session's tree, which is rebuilt as SwiftMutator's
//  `ProjectTree.applying(_:)` does; the reader checks that it hashes to
//  the tree the change names.
//

import Foundation

/// Project trees as SwiftMutator records them.
enum MutationTree {
    /// What a symbolic link's hash starts with.
    static let linkPrefix = "link:"

    /// The tree hash of `files`: the SHA-256 over every
    /// `path\0hash\n`, sorted by the paths' UTF-8 bytes.
    static func hash(of files: [String: String]) -> String {
        let lines = files.keys
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            .map { "\($0)\0\(files[$0] ?? "")\n" }
            .joined()
        return ContentHash.sha256(Data(lines.utf8))
    }

    /// `base` with `files` added or replaced and `removed` dropped.
    static func applying(files: [String: String], removed: [String], to base: [String: String]) -> [String: String] {
        var tree = base.merging(files) { _, recorded in recorded }
        for path in removed {
            tree.removeValue(forKey: path)
        }
        return tree
    }
}
