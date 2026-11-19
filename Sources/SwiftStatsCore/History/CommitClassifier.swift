//
//  CommitClassifier.swift
//  SwiftStatsCore
//
//  Classifies commits for history (PRD §7.13): sweeps, ignored commits, fixes,
//  reverts and the tests each commit changed.
//

import Foundation

/// Classifies commits.
struct CommitClassifier {
    /// The shortest abbreviated commit hash `.git-blame-ignore-revs` may list.
    private static let minimumHashLength = 7

    /// Compiled fix patterns.
    private let fixPatterns: [NSRegularExpression]
    /// Compiled fix-exclusion patterns.
    private let excludePatterns: [NSRegularExpression]
    /// Ignored commits, lowercased, full or abbreviated.
    private let ignored: [String]
    /// The sweep threshold.
    private let bulkFiles: Int
    /// The first second of the window.
    private let windowStart: Int
    /// Where each file belongs.
    private let modules: ModuleMap

    /// A classifier for `options`, with `ignored` commits from
    /// `.git-blame-ignore-revs` added to the configured ones.
    init(options: HistoryOptions, ignored: [String], windowStart: Int, modules: ModuleMap) {
        fixPatterns = Self.compile(options.fixPatterns)
        excludePatterns = Self.compile(options.fixExcludePatterns)
        self.ignored = (options.ignoreRevs + ignored).map { hash in hash.lowercased() }
        bulkFiles = options.bulkFiles
        self.windowStart = windowStart
        self.modules = modules
    }

    /// The hashes listed in a `.git-blame-ignore-revs` file.
    static func ignoreRevs(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let hash = content.trimmingCharacters(in: .whitespaces).lowercased()
            return hash.count >= minimumHashLength && hash.allSatisfy(\.isHexDigit) ? hash : nil
        }
    }

    /// The case-insensitive regular expressions among `patterns`; one that
    /// doesn't compile is left out.
    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }

    /// Whether any of `patterns` matches `text`.
    private static func matches(_ patterns: [NSRegularExpression], _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { pattern in pattern.firstMatch(in: text, range: range) != nil }
    }

    /// The facts of `commit`.
    func facts(of commit: HistoryCommit) -> CommitFacts {
        var files = 0
        var testNames: Set<String> = []
        for change in commit.changes {
            let places = [change.oldPath, change.newPath].compactMap(\.self).compactMap { path in
                modules.place(path).map { (path, $0.isTest) }
            }
            if places.isEmpty == false {
                files += 1
            }
            for (path, isTest) in places where isTest {
                testNames.insert(TestNameMatcher.testName(of: path))
            }
        }
        let hash = commit.hash.lowercased()
        var sweepReason: String?
        if ignored.contains(where: { hash.hasPrefix($0) }) {
            sweepReason = "ignored"
        } else if files > bulkFiles {
            sweepReason = "sweep"
        }
        return CommitFacts(
            time: commit.time,
            inWindow: commit.time >= windowStart,
            files: files,
            sweepReason: sweepReason,
            matchesFix: Self.matches(fixPatterns, commit.subject),
            excludedSubject: Self.matches(excludePatterns, commit.subject),
            isRevertCommit: commit.subject.hasPrefix("Revert ") || commit.subject.hasPrefix("Revert\"")
                || commit.body.contains("This reverts commit"),
            testNames: testNames
        )
    }
}
