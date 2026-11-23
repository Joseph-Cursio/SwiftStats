//
//  MutationCounts.swift
//  SwiftStatsCore
//
//  A set of mutants counted by verdict (M6, design §3, §4): a record's, an
//  attachment's, or every mutant's. Kills a test process crashed for are
//  counted among the kills and again apart, and the kills only suspect
//  tests made (flags judged true) are counted too, with how many kills by
//  a failing test were judged at all (true or false), so a figure can say
//  how much of its suspect evidence was looked at. The scores are worked
//  out from the counts (`MutationFigures`). The scan JSON writes the
//  counts beside the fields of what they count, not nested.
//

/// Mutants counted by verdict.
public struct MutationCounts: Codable, Hashable, Sendable {
    /// Killed: a test failed, or a test process crashed.
    public let killed: Int
    /// Of the kills, those a test process crashed for.
    public let crashKills: Int
    /// Ran, and every test passed.
    public let survived: Int
    /// Made and tested, but their blocks never ran.
    public let noCoverage: Int
    /// Stopped at their time limit.
    public let timedOut: Int
    /// In code no test ran: listed by key, never made.
    public let notCovered: Int
    /// Not built.
    public let buildErrors: Int
    /// Of the kills, those only suspect tests made.
    public let suspectOnly: Int
    /// Of the kills by a failing test, those whose suspect flag was judged,
    /// true or false; the rest weren't judged.
    public let judgedKills: Int

    /// Creates counts. Fields are documented on their properties.
    public init(
        killed: Int,
        crashKills: Int,
        survived: Int,
        noCoverage: Int,
        timedOut: Int,
        notCovered: Int,
        buildErrors: Int,
        suspectOnly: Int,
        judgedKills: Int
    ) {
        self.killed = killed
        self.crashKills = crashKills
        self.survived = survived
        self.noCoverage = noCoverage
        self.timedOut = timedOut
        self.notCovered = notCovered
        self.buildErrors = buildErrors
        self.suspectOnly = suspectOnly
        self.judgedKills = judgedKills
    }

    /// `mutants` counted.
    init(_ mutants: [Mutant]) {
        let verdicts = mutants.map(\.verdict)
        self.init(
            killed: verdicts.count { $0 == .killed },
            crashKills: mutants.count(where: \.isCrashKill),
            survived: verdicts.count { $0 == .survived },
            noCoverage: verdicts.count { $0 == .noCoverage },
            timedOut: verdicts.count { $0 == .timedOut },
            notCovered: verdicts.count { $0 == .notCovered },
            buildErrors: verdicts.count { $0 == .buildError },
            suspectOnly: mutants.count { $0.suspectOnly?.value == true },
            judgedKills: mutants.count { $0.verdict == .killed && $0.isCrashKill == false && $0.suspectOnly != nil }
        )
    }
}
