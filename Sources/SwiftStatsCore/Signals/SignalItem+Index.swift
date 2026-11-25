//
//  SignalItem+Index.swift
//  SwiftStatsCore
//
//  The payloads M7's signals fill from the T1 build (design §8): for
//  test-only production code, a function's references from test targets,
//  counted as distinct test containers with the first five named, and its
//  module; for dead but tested, the unused declaration outskirts' run with
//  tests not counted as roots reports covering the function, by which
//  rule, and whether the run with tests as roots covers it too; the
//  coverage setting of the mutation run a dead but tested function's
//  mutants come from; and for hidden coupling, the pair's partner family,
//  how often each family and both changed in the window, and whether the
//  two share a file or a module.
//

public extension SignalItem {
    /// Where a function's references come from, for a signal reading the
    /// index's referrers.
    struct References: Codable, Hashable, Sendable {
        /// Distinct test containers referencing it.
        public let tests: Int
        /// The first five of them, as the index block names them: record
        /// keys, or symbol names for containers that aren't records,
        /// sorted in code point order.
        public let testReferrers: [String]
        /// Its module, a target name.
        public let module: String
    }

    /// The unused declaration covering a production-dead function, as
    /// outskirts' `production` run reports it.
    struct Dead: Codable, Hashable, Sendable {
        /// outskirts' kind of the declaration, such as `function.free` or
        /// `struct`.
        public let kind: String
        /// The declaration's name.
        public let name: String
        /// Its file in the package; nil outside the root.
        public let file: String?
        /// The 1-based line of its name.
        public let line: Int
        /// The rule by which it covers the function: `usr` and `property`
        /// need the index, `type` and `extension` apply with or without
        /// it, and `location` only without it.
        public let via: DeadCodeVia
        /// Its accessibility, as outskirts writes it.
        public let accessibility: String
        /// Whether the `roots` run covers the function too, or a function
        /// it is nested in: no test references it statically either, so
        /// tests reach it dynamically.
        public let deadWithTestsAsRoots: Bool
    }

    /// A pair of families changed together, for hidden coupling: the
    /// item's subject is the pair's first family, in key order, and this
    /// names its partner.
    struct Coupling: Codable, Hashable, Sendable {
        /// The partner family's key.
        public let partner: String
        /// Its file.
        public let partnerFile: String
        /// Commits in the window changing both families.
        public let support: Int
        /// Commits in the window changing the subject's family.
        public let changesA: Int
        /// Commits in the window changing the partner's.
        public let changesB: Int
        /// Support of the less-changed family's changes.
        public let confidence: CouplingConfidence
        /// The two families' targets, the subject's first.
        public let modules: [String]
        /// Whether the two families are in one file.
        public let sameFile: Bool
        /// Whether they are in one target.
        public let sameModule: Bool
    }

    /// A coupling pair's confidence as its two integers, so a reader can
    /// divide: support of the less-changed family's changes.
    struct CouplingConfidence: Codable, Hashable, Sendable {
        /// Commits in the window changing both families.
        public let support: Int
        /// Commits in the window changing the less-changed family.
        public let smaller: Int
    }

    /// Whether a function's mutation run had coverage on: SwiftMutator
    /// mutates only code tests ran, or, with coverage off, all of it.
    enum CoverageSetting: String, Codable, Sendable {
        /// Coverage off: a mutant in code no test runs reads as survived.
        case disabled = "off"
        /// Coverage on: mutants are made only in code tests ran.
        case enabled = "on"
    }
}
