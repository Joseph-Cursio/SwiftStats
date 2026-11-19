//
//  HistoryOptions.swift
//  SwiftStatsCore
//
//  `history:` in `.swiftstats.yml` (PRD §7.13, §10.1): the churn window,
//  how fix and revert commits are recognised, which commits are sweeps, and
//  the change-coupling floor. Every value is recorded in the history
//  collector's options, so two runs with different settings never compare.
//

import Foundation

/// How the history collector reads git history.
public struct HistoryOptions: Hashable, Sendable {
    /// The default subject patterns of a fix commit.
    public static let defaultFixPatterns = [#"^(fix|fixes|fixed)\b"#, #"\bbug\b"#, #"\bregression\b"#, #"^hotfix\b"#]
    /// The default subject patterns that stop a matching commit counting as a fix.
    public static let defaultFixExcludePatterns = [
        #"\b(swiftlint|lint|violations?|warnings?)\b"#,
        #"^(style|chore)(\(.*\))?:"#
    ]
    /// The default churn window, in days.
    private static let defaultWindowDays = 90
    /// The default repeated-fix window, in days.
    private static let defaultRepeatWindowDays = 14
    /// The default fix half-life, in days.
    private static let defaultHalfLifeDays = 90
    /// The default sweep threshold, in Swift files changed by one commit.
    private static let defaultBulkFiles = 30
    /// The default change-coupling support floor.
    private static let defaultCouplingMinSupport = 3
    /// The defaults.
    public static let standard = Self(
        windowDays: defaultWindowDays,
        fixPatterns: defaultFixPatterns,
        fixExcludePatterns: defaultFixExcludePatterns,
        repeatWindowDays: defaultRepeatWindowDays,
        halfLifeDays: defaultHalfLifeDays,
        bulkFiles: defaultBulkFiles,
        ignoreRevs: [],
        couplingMinSupport: defaultCouplingMinSupport
    )

    /// Days before the analysed commit whose commits count as recent churn.
    public let windowDays: Int
    /// Case-insensitive regular expressions; a commit whose subject matches
    /// one is a fix, unless it is excluded.
    public let fixPatterns: [String]
    /// Case-insensitive regular expressions; a matching subject is never a fix.
    public let fixExcludePatterns: [String]
    /// A fix within this many days after another fix to the same function
    /// is a repeated fix.
    public let repeatWindowDays: Int
    /// The age in days at which a fix counts half toward the fix score.
    public let halfLifeDays: Int
    /// A commit changing more of the package's Swift files than this is a
    /// sweep: it is left out of churn, fixes and coupling.
    public let bulkFiles: Int
    /// Commits (full or abbreviated hashes) treated as sweeps, besides those
    /// in the repository's `.git-blame-ignore-revs`.
    public let ignoreRevs: [String]
    /// Pairs of functions changed together in fewer commits than this are
    /// not reported as coupled.
    public let couplingMinSupport: Int

    /// The options as the history collector's run records them, in a fixed order.
    var recorded: [String] {
        [
            "window: \(windowDays)d",
            "fix_patterns: \(fixPatterns.joined(separator: " | "))",
            "fix_exclude_patterns: \(fixExcludePatterns.joined(separator: " | "))",
            "repeat_window: \(repeatWindowDays)d",
            "half_life: \(halfLifeDays)d",
            "bulk_files: \(bulkFiles)",
            "ignore_revs: \(ignoreRevs.joined(separator: " "))",
            "coupling.min_support: \(couplingMinSupport)"
        ]
    }

    /// Options. Fields are documented on their properties.
    public init(
        windowDays: Int,
        fixPatterns: [String],
        fixExcludePatterns: [String],
        repeatWindowDays: Int,
        halfLifeDays: Int,
        bulkFiles: Int,
        ignoreRevs: [String],
        couplingMinSupport: Int
    ) {
        self.windowDays = windowDays
        self.fixPatterns = fixPatterns
        self.fixExcludePatterns = fixExcludePatterns
        self.repeatWindowDays = repeatWindowDays
        self.halfLifeDays = halfLifeDays
        self.bulkFiles = bulkFiles
        self.ignoreRevs = ignoreRevs
        self.couplingMinSupport = couplingMinSupport
    }
}
