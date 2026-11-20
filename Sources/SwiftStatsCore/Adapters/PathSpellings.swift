//
//  PathSpellings.swift
//  SwiftStatsCore
//
//  The ways a tool can write a temporary directory's path. On macOS `/var`
//  and `/tmp` are symlinks into `/private`, and a tool that asks for its
//  working directory gets the `/private` spelling, while Foundation drops
//  `/private` when it resolves symlinks.
//

import Foundation

/// Spellings of a directory's path.
enum PathSpellings {
    /// The prefix macOS's `/var` and `/tmp` resolve under.
    private static let privatePrefix = "/private"

    /// `directory` as given, standardized, with symlinks resolved, and
    /// each with and without `/private`; longest first, since a shorter
    /// spelling can lie inside a longer one.
    static func of(_ directory: URL) -> [String] {
        var spellings = Set<String>()
        for path in [directory.standardizedFileURL.path, directory.resolvingSymlinksInPath().path] {
            spellings.insert(path)
            if path.hasPrefix(privatePrefix + "/") {
                spellings.insert(String(path.dropFirst(privatePrefix.count)))
            } else {
                spellings.insert(privatePrefix + path)
            }
        }
        return spellings.sorted { ($0.count, $0) > ($1.count, $1) }
    }
}
