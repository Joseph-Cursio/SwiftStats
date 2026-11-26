//
//  UntestedProperty.swift
//  SwiftStatsCore
//
//  Untested property (PRD §8): a concrete property test to write. The pool
//  is SwiftInferProperties' algebraic suggestions located in production
//  code and attached to a production function outside generated files,
//  scoring in the Strong band or lifted to Verified by fresh evidence,
//  neither disproven nor rejected. Strong rows held at Advisory by a
//  structural blocker stay in, flagged. Every suggestion no property test
//  was found for is listed, scored by its score plus Verified's 50; the
//  signal isn't ranked.
//

/// The untested-property signal.
enum UntestedProperty {
    /// What fresh `measured-bothPass` evidence adds to a score, as
    /// SwiftInferProperties' own Verified rule does.
    static let verifiedBonus = 50

    /// The rule as reports state it, before the package is known.
    static let rule = "algebraic suggestions on production functions, in the Strong band or Verified, "
        + "neither disproven nor rejected, that no property test checks"

    /// The signal over `snapshot`. Each item is scored by `itemScore`, so a
    /// tool score as large as an `Int` holds is listed instead of trapping.
    static func compute(_ snapshot: StoredSnapshot) -> SignalComputation {
        let functions = ProductionFunctions(snapshot)
        let pool = snapshot.candidates.filter { candidate in
            guard candidate.population == .algebraic, candidate.site == .production,
                  functions.row(of: candidate) != nil else {
                return false
            }
            let judgement = candidate.verification?.judgement
            let strong = candidate.scoreBand == .strong || judgement?.verified == true
            return strong && judgement?.disproven != true && candidate.decision != .rejected
        }
        let hasTests = snapshot.functions.contains { $0.role == .test || $0.role == .helper }
        let noTestTarget = "; the package has no test target, so no test can be found"
        return SignalComputation(
            rule: rule + (hasTests ? "" : noTestTarget),
            candidates: pool.count,
            scored: pool.compactMap { candidate in
                guard candidate.testedBy == nil, let row = functions.row(of: candidate) else {
                    return nil
                }
                let property = SignalItem.Property(candidate)
                let score = itemScore(candidate.score, verified: property.verified)
                let draft = SignalItem.Draft(subject: row.key, file: row.file, line: row.startLine, property: property)
                // A function can carry several suggestions: the identity
                // breaks the last tie.
                let order = SignalSortKey.standard(score: score, subject: row.key, file: row.file, line: row.startLine)
                return SignalScore(draft, score: score, sortKey: order.appending(.text(candidate.identity)))
            }
        )
    }

    /// `score` plus Verified's 50 when `verified`, as the item's `Double`
    /// score. The sum is taken in `Int` and rounded once; only a sum past an
    /// `Int`'s end, which lies within 50 of it, is added in `Double` instead,
    /// where it rounds to the same value the exact sum would.
    static func itemScore(_ score: Int, verified: Bool) -> Double {
        let bonus = verified ? verifiedBonus : 0
        let (sum, overflow) = score.addingReportingOverflow(bonus)
        return overflow ? Double(score) + Double(bonus) : Double(sum)
    }
}
