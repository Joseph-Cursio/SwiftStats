//
//  MutationMerge+Paths.swift
//  SwiftStatsCore
//
//  What a `--since` merge looks up by path (M6, design §6.1), every path
//  in its NFC spelling (`NFCPath`), as SwiftMutator's own report looks
//  paths up: the
//  base's tree (its deleted paths left out) and rows, the new tree's Swift
//  paths (the run's last header's, or the copy's own hashes when the run
//  wrote no results file), the paths the run has a mutant in, the ones it
//  chose, and SwiftMutator's selection as SwiftStats worked it out.
//

import Foundation

extension MutationMerge {
    /// The paths a merge decides on, and what it knows of each.
    struct Paths {
        /// What a Swift file's name ends with.
        private static let swiftSuffix = ".swift"

        /// The base's tree, deleted paths left out.
        let baseTree: [NFCPath: MutationFile]
        /// The base's rows, by path.
        let baseRows: [NFCPath: [Mutant]]
        /// The new tree's Swift paths: each one's spelling there, and its
        /// hash.
        let newTree: [NFCPath: (path: String, sha256: String)]
        /// The paths the run has a mutant in, tested or not covered.
        let freshPaths: Set<NFCPath>
        /// The paths the run chose (`since.files`), test files among them.
        let chosen: Set<NFCPath>
        /// The paths SwiftMutator's selection holds, as SwiftStats worked
        /// it out in the copy.
        let selection: Set<NFCPath>

        /// Every path to decide on, sorted.
        var all: [NFCPath] {
            Set(baseTree.keys).union(baseRows.keys).union(newTree.keys).union(freshPaths).sorted()
        }

        /// The paths of `base`, of `results` (nil when the run wrote no
        /// results file) and of `changes`.
        init(base: MutationBase, results: MutationResults?, changes: MutationChanges) {
            let normalized = NFCPath.init
            let earlier = base.report.files.filter { $0.disposition != .deleted && $0.sha256 != nil }
            baseTree = Dictionary(earlier.map { (normalized($0.path), $0) }) { first, _ in first }
            baseRows = Dictionary(grouping: base.report.mutants) { normalized($0.path) }
            let tree = (results?.tree ?? changes.tree).filter { $0.key.hasSuffix(Self.swiftSuffix) }
            let entries = tree.map { path, hash in (normalized(path), (path: path, sha256: hash)) }
            newTree = Dictionary(entries) { first, _ in first }
            freshPaths = Set((results?.mutants ?? []).map { normalized($0.key.path) })
            chosen = Set((results?.facts.since?.files ?? []).map { normalized($0.path) })
            selection = Set(changes.selection.map(normalized))
        }

        /// Whether the base's rows at `path` belong to no tree: a path
        /// neither tree lists nor the run tested (a mutant SwiftMutator
        /// dropped by design outside the listing), whose rows are kept.
        func isRowsOnly(_ path: NFCPath) -> Bool {
            baseTree[path] == nil && newTree[path] == nil && freshPaths.contains(path) == false
        }
    }
}
