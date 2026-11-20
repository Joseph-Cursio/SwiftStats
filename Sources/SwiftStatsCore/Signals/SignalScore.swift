//
//  SignalScore.swift
//  SwiftStatsCore
//
//  What a signal's scorer gives for one candidate it lists: the item, its
//  score, and where it sorts. A non-ranked signal's scorer gives nothing
//  for a candidate that isn't a member, so everything it lists is one.
//

/// A scored, not yet ranked, item.
struct SignalScore: Hashable, Sendable {
    /// The item.
    let draft: SignalItem.Draft
    /// Its score.
    let score: Double
    /// Where it sorts.
    let sortKey: SignalSortKey

    /// `draft` with `score`, sorting by score, highest first, then
    /// subject, file and line.
    init(_ draft: SignalItem.Draft, score: Double) {
        self.init(
            draft,
            score: score,
            sortKey: .standard(score: score, subject: draft.subject, file: draft.file, line: draft.line)
        )
    }

    /// `draft` with `score`, sorting by `sortKey`.
    init(_ draft: SignalItem.Draft, score: Double, sortKey: SignalSortKey) {
        self.draft = draft
        self.score = score
        self.sortKey = sortKey
    }
}
