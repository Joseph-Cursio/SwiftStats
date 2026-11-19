//
//  HistorySource.swift
//  SwiftStatsCore
//
//  Whether and where a scan reads history (PRD §7.13): the scanned tree's HEAD, a
//  named commit of a repository, or not at all.
//

import Foundation

/// Whether and where a scan reads history.
public enum HistorySource: Sendable {
    /// Read the history of the scanned tree's HEAD, when it is in git.
    case automatic
    /// Read the history of `commit` in the repository whose top level is
    /// `top`, for the package at `packagePath` from that top level.
    case commit(top: URL, commit: String, packagePath: String)
    /// Don't read history, for `reason`.
    case skipped(String)

    /// The source with `automatic` resolved for the package at
    /// `packageRoot`, whose git state is `git`.
    func resolved(packageRoot: URL, git: GitState) -> Self {
        guard case .automatic = self else {
            return self
        }
        guard let commit = git.commit,
              let top = GitReader.line(["rev-parse", "--show-toplevel"], in: packageRoot) else {
            return .skipped("not in a git repository with commits")
        }
        return .commit(top: URL(fileURLWithPath: top), commit: commit, packagePath: git.packagePath)
    }
}
