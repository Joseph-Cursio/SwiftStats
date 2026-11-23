//
//  SuspectJudgement.swift
//  SwiftStatsCore
//
//  Whether a kill was made only by suspect tests (M6, design §2): a
//  tri-state, since SwiftMutator judges reach only when enough files have
//  kills naming tests (`suspectsChecked`), and only a kill by a failed test
//  can be suspect-only.
//

/// Whether a kill was made only by suspect tests.
enum SuspectJudgement: String, Sendable {
    /// Judged: a test that isn't suspect failed for it.
    case notSuspectOnly
    /// Every test named failing for it is suspect.
    case suspectOnly
    /// Not judged: suspects weren't checked, the report gave no summary,
    /// or the mutant isn't a kill by a failed test.
    case unjudged

    /// The flag the scan JSON writes for it: true, false, or none.
    var flag: JSONFlag? {
        switch self {
        case .suspectOnly:
            JSONFlag(true)

        case .notSuspectOnly:
            JSONFlag(false)

        case .unjudged:
            nil
        }
    }
}
