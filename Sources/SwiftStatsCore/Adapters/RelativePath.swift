//
//  RelativePath.swift
//  SwiftStatsCore
//
//  Tools report paths relative to the project root or absolute; findings
//  store them relative to the package root.
//

import Foundation

/// Paths relative to the package root.
enum RelativePath {
    /// `path` relative to `root` when it is absolute and inside it, else as given.
    static func of(_ path: String, under root: URL) -> String {
        guard path.hasPrefix("/") else {
            let current = "./"
            return path.hasPrefix(current) ? String(path.dropFirst(current.count)) : path
        }
        let file = URL(fileURLWithPath: path)
        for candidate in [file.standardizedFileURL.path, file.resolvingSymlinksInPath().path] {
            for base in [root.standardizedFileURL.path, root.resolvingSymlinksInPath().path] {
                let prefix = base.hasSuffix("/") ? base : base + "/"
                if candidate.hasPrefix(prefix) {
                    return String(candidate.dropFirst(prefix.count))
                }
            }
        }
        return path
    }
}
