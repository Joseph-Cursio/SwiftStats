//
//  SignalItem+Mutation.swift
//  SwiftStatsCore
//
//  The payloads M6's signals fill (design §7): a function's mutants
//  counted by verdict with both scores, its killing tests (a lower bound),
//  the mutants its tests ran and didn't check, and the suspect tests behind
//  its suspect-only kills with why (for reach, in how many of the files
//  with kills each failed); and the test-to-code line ratio of its module
//  and of the project, which weak tests shows as context and genuinely
//  under-tested judges by.
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
        /// then the reach figures (none first).
        public let suspects: [Suspect]
    }

    /// A suspect test behind a suspect-only kill.
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
}
