//
//  FileChange.swift
//  SwiftStatsCore
//
//  One file a commit changed, with the blobs and paths on each side.
//

/// One file a commit changed.
struct FileChange: Hashable, Sendable {
    /// Git's status letter: A, M, D, R, C or T.
    let status: Character
    /// The path before, relative to the package root; nil when added, or
    /// when it came from outside the package.
    let oldPath: String?
    /// The path after, relative to the package root; nil when deleted, or
    /// when it moved outside the package.
    let newPath: String?
    /// The blob before; nil when there was none.
    let oldBlob: String?
    /// The blob after; nil when there is none.
    let newBlob: String?
}
