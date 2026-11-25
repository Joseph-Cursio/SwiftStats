//
//  SignalItem+Mutation.swift
//  SwiftStatsCore
//
//  The payloads M6's signals fill (design §7): a function's mutants
//  counted by verdict with both scores, its killing tests (a lower bound),
//  the mutants its tests ran and didn't check, and the suspect tests behind
//  its suspect-only kills with why (for reach, in how many of the files
//  with kills each failed); the test-to-code line ratio of its module
//  and of the project, which weak tests shows as context and genuinely
//  under-tested judges by; for best property-test target, the
//  function's suggestions, its unkilled mutants and its resolved partners';
//  and, for uneven clone testing's mutation part, each measured copy's
//  mutants killed and scored, split into those that ran unchecked and those
//  in code that never ran. M7's dead but tested adds the coverage setting
//  of a function's mutation run.
//

public extension SignalItem {
    /// A function's mutation results.
    struct Mutation: Codable, Hashable, Sendable {
        /// Its mutants by verdict, crash kills, suspect-only kills and the
        /// kills by a failing test whose suspect flag was judged.
        public let counts: MutationCounts
        /// SwiftMutator's mutation score over its mutants.
        public let score: MutationScore
        /// The function score: not-covered mutants counted as unkilled.
        public let functionScore: MutationScore
        /// How many distinct tests its kills name.
        public let killingTests: Int
        /// The first of them, sorted, at most five.
        public let firstKillingTests: [String]
        /// Its survived and timed-out mutants: those the tests ran and
        /// didn't check, in the report's order.
        public let survivors: [UncheckedMutant]
        /// The suspect tests its suspect-only kills name, by name, then why,
        /// then the reach figures (none first), each distinct entry once.
        /// A kill names its tests by name only, so every suspect test of
        /// the run with that name is matched, a same-named test in another
        /// file included; with no file in an entry, same-named tests
        /// suspect for the same reason with the same figures show as one.
        public let suspects: [Suspect]
        /// Whether its file's mutation run had coverage on, for dead but
        /// tested (M7), which counts only the kills of a run with coverage
        /// off; nil, and left out of the JSON, for the other signals, and
        /// for dead but tested when the setting isn't known (its file names
        /// no run and its mutants' runs differ).
        public let coverage: CoverageSetting?

        /// These results with `setting` as their run's coverage setting,
        /// nil when it isn't known.
        func with(coverage setting: CoverageSetting?) -> Self {
            Self(
                counts: counts,
                score: score,
                functionScore: functionScore,
                killingTests: killingTests,
                firstKillingTests: firstKillingTests,
                survivors: survivors,
                suspects: suspects,
                coverage: setting
            )
        }
    }

    /// A suspect test behind a suspect-only kill, matched to the kill by
    /// name alone: SwiftMutator judges suspects by name and file, but a
    /// kill's `killedBy` keeps only names, so every same-named suspect is
    /// matched rather than one guessed. An entry carries no file, so each
    /// distinct mix of name, why and reach figures is listed once:
    /// same-named tests in different files suspect for the same reason
    /// show as one.
    struct Suspect: Codable, Hashable, Sendable {
        /// Its name, as SwiftMutator records it.
        public let name: String
        /// Why it is suspect: `controlRun`, `flaky` or `reach`.
        public let why: String
        /// For `reach`: how many files with kills it failed in; nil for
        /// the other reasons.
        public let files: Int?
        /// For `reach`: how many files have a kill naming a test; nil for
        /// the other reasons.
        public let filesWithKills: Int?
    }

    /// The test-to-code line ratio of an item's module and of the project.
    struct Ratio: Codable, Hashable, Sendable {
        /// The module's name.
        public let module: String
        /// The module's lines; nil when its roll-up holds none.
        public let moduleLines: RatioLines?
        /// The project's lines; nil when its roll-up holds none.
        public let projectLines: RatioLines?
    }

    /// The stripped lines behind a test-to-code ratio.
    struct RatioLines: Codable, Hashable, Sendable {
        /// Test lines measured against the code.
        public let testLines: Int
        /// The code's production lines.
        public let productionLines: Int
    }

    /// What best property-test target lists for a function: its
    /// suggestions, the mutants its tests don't kill, and the partners of
    /// its two-function suggestions with theirs.
    struct PropertyTarget: Codable, Hashable, Sendable {
        /// Its suggestions in the pool, best first: score with Verified's
        /// bonus, highest first, then identity.
        public let suggestions: [Property]
        /// Its survived, timed-out, no-coverage and not-covered mutants, in
        /// the report's order.
        public let unkilled: [UncheckedMutant]
        /// The resolved partners of its two-function suggestions, by key.
        public let partners: [Partner]
    }

    /// The partner of a two-function suggestion: a production function
    /// the property runs too.
    struct Partner: Codable, Hashable, Sendable {
        /// Its record's key.
        public let key: String
        /// Its mutants counted; nil when it has none.
        public let counts: MutationCounts?
        /// Its survived, timed-out, no-coverage and not-covered mutants, in
        /// the report's order.
        public let unkilled: [UncheckedMutant]
    }

    /// How the tests kill the mutants of a clone class's copies (uneven
    /// clone testing, mutation part).
    struct CloneMutation: Codable, Hashable, Sendable {
        /// The ordinals of the classes folded into this item, sorted.
        public let folded: [Int]
        /// The measured copies, in the class's order.
        public let copies: [MutatedCopy]
    }

    /// One clone copy with its mutants: those anchored in its range.
    struct MutatedCopy: Codable, Hashable, Sendable {
        /// Its file.
        public let file: String
        /// Where it starts.
        public let line: Int
        /// The family holding it, by M4's copy-to-family rule: the first
        /// family it covers whole, else its containing record's family;
        /// `<file>:<line>` when neither exists.
        public let family: String
        /// Its mutants killed.
        public let killed: Int
        /// Its scored mutants: killed, survived, no coverage, timed out
        /// and not covered (build errors aside).
        public let scored: Int
        /// Its mutants that ran and no test checked: survived and timed out.
        public let runButUnchecked: Int
        /// Its mutants whose code never ran: no coverage and not covered.
        public let unrun: Int
    }
}
