//
//  NameStatusEntry.swift
//  SwiftStatsCoreTests
//
//  One entry of `git diff --name-status -z` as decisions, for P14.2: its
//  status, a similarity score for a copy or rename, and its paths, two for
//  a copy or rename (the old, then the new) and one otherwise. git writes
//  the status and each path as their own NUL-ended fields, the status as
//  its letter and, for a copy or rename, the score in three digits
//  (`R100`, `C075`, `R007`).
//

/// One entry of `git diff --name-status -z` as decisions.
struct NameStatusEntry: Hashable, Sendable {
    /// What happened to the path.
    enum Status: Hashable, Sendable, CaseIterable {
        /// `A`: added.
        case added
        /// `C<score>`: copied.
        case copied
        /// `D`: deleted.
        case deleted
        /// `M`: modified.
        case modified
        /// `R<score>`: renamed.
        case renamed
        /// `T`: its type changed.
        case typeChanged
        /// `X`: unknown to git.
        case unknown
        /// `U`: unmerged.
        case unmerged

        /// Whether an entry of this status names two paths.
        var hasTwoPaths: Bool {
            self == .copied || self == .renamed
        }
    }

    /// What happened to the path.
    let status: Status
    /// The similarity score of a copy or rename, 0 to 100.
    let score: Int
    /// The paths: the old and the new of a copy or rename, else the one.
    let paths: [String]

    /// The status as git writes it.
    var written: String {
        switch status {
        case .added:
            return "A"

        case .copied:
            return "C" + padded(score)

        case .deleted:
            return "D"

        case .modified:
            return "M"

        case .renamed:
            return "R" + padded(score)

        case .typeChanged:
            return "T"

        case .unknown:
            return "X"

        case .unmerged:
            return "U"
        }
    }

    /// The entry's fields: the status, then its paths.
    var fields: [String] {
        [written] + paths
    }

    /// `score` in three digits, as git writes it.
    private func padded(_ score: Int) -> String {
        let digits = String(score)
        return String(repeating: "0", count: max(0, NameStatusDraft.scoreWidth - digits.count)) + digits
    }
}
