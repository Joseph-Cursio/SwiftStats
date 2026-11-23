//
//  MutationGaps.swift
//  SwiftStatsCore
//
//  The files whose mutants a snapshot's mutation results leave out (M6,
//  review finding 9): changed files a `--since` merge left unlisted (no
//  results file, so their code no test ran isn't listed) or unresolved (no
//  results at all), and results that are otherwise incomplete. Their rows
//  are dropped, while the roll-up counts are still stored, so those counts
//  shrink by mutants no run looked at. `diff` and `trend` therefore don't
//  compare a side's mutation counts above records when it has gaps; the
//  roll-up score stays compared (exact for unlisted files, left out
//  when incomplete), as do the records' own figures (a record with no
//  mutant is not collected), and the carried count is a fact either way.
//

/// What a snapshot's mutation results leave out.
struct MutationGaps: Hashable, Sendable {
    /// The roll-up metric that stays compared beside gaps: the score.
    private static let comparedScore = "mutation.score.percent"
    /// Roll-up numbers that are facts of where results came from.
    private static let provenance = "mutation.carried"
    /// What a mutation roll-up metric's path starts with.
    private static let prefix = "mutation."

    /// Changed files whose code no test ran isn't listed.
    let unlisted: Int
    /// Changed files with no results.
    let unresolved: Int
    /// Whether the results are complete.
    let complete: Bool

    /// Whether nothing is left out.
    var isEmpty: Bool {
        complete && unlisted == 0 && unresolved == 0
    }

    /// What is left out, in words: `1 unlisted, 2 unresolved`, or that
    /// mutants have no result.
    var description: String {
        var parts: [String] = []
        if unlisted > 0 {
            parts.append("\(unlisted) unlisted")
        }
        if unresolved > 0 {
            parts.append("\(unresolved) unresolved")
        }
        if complete == false, unresolved == 0 {
            parts.append("mutants without a result")
        }
        return parts.joined(separator: ", ")
    }

    /// The gaps of results with `unlisted` and `unresolved` files, complete
    /// or not.
    init(unlisted: Int, unresolved: Int, complete: Bool) {
        self.unlisted = unlisted
        self.unresolved = unresolved
        self.complete = complete
    }

    /// The gaps of `report`; nil when it leaves nothing out.
    init?(_ report: MutationReport) {
        self.init(
            unlisted: report.files.count { $0.disposition == .unlisted },
            unresolved: report.files.count { $0.disposition == .unresolved },
            complete: report.complete
        )
        guard isEmpty == false else {
            return nil
        }
    }

    /// Whether roll-up metric `metric` is a mutation count that gaps make
    /// unlike: every `mutation.` number but the score and the carried count.
    static func affects(_ metric: String) -> Bool {
        metric.hasPrefix(prefix) && metric != comparedScore && metric != provenance
    }
}
