//
//  PropertyCandidate.swift
//  SwiftStatsCore
//
//  One property-test suggestion of SwiftInferProperties (PRD §7.11): a
//  row of `swift-infer index`, merged over the package's targets and
//  attached to the function record it names, or listed as unmapped; then
//  joined to the package's own decisions and verify evidence, and linked to
//  the property tests that check it. The verify join is grouped, since
//  SwiftLint's discouraged_optional_boolean rules out the nullable Booleans
//  a flat join would need: the group is nil when the package has no
//  readable verify evidence, and its judgement nil when evidence names an
//  interaction row, whose index row carries no subject fingerprint to
//  compare it with.
//

/// A property-test suggestion and where it attaches.
public struct PropertyCandidate: Codable, Hashable, Sendable {
    /// What the package's `.swiftinfer/decisions.json`, or for an
    /// interaction row its `interaction-decisions.json`, records.
    public enum Decision: String, Codable, CaseIterable, Sendable {
        /// Accepted.
        case accepted
        /// Accepted as a conformance to a kit protocol: written
        /// `acceptedAsConformance`, or `accepted-as-conformance` for an
        /// interaction row.
        case asConformance = "acceptedAsConformance"
        /// Rejected: hidden from later runs.
        case rejected
        /// Skipped: acknowledged but undecided.
        case skipped
    }

    /// Which of the index's lists the suggestion comes from.
    public enum Population: String, Codable, CaseIterable, Sendable {
        /// `entries`: a template law on one or two functions.
        case algebraic
        /// `interactionEntries`: a reducer or view-model invariant.
        case interaction
    }

    /// The band SwiftInferProperties' own rule gives the score, whatever
    /// tier the row is written with.
    public enum ScoreBand: String, Codable, CaseIterable, Sendable {
        /// A score of 40 to 74.
        case likely = "Likely"
        /// A score of 20 to 39.
        case possible = "Possible"
        /// A score of 75 or more.
        case strong = "Strong"
        /// A score below 20.
        case suppressed = "Suppressed"

        /// Lowest score of the Strong band.
        private static let strongScore = 75
        /// Lowest score of the Likely band.
        private static let likelyScore = 40
        /// Lowest score of the Possible band.
        private static let possibleScore = 20

        /// The band of `score`.
        init(score: Int) {
            if score >= Self.strongScore {
                self = .strong
            } else if score >= Self.likelyScore {
                self = .likely
            } else if score >= Self.possibleScore {
                self = .possible
            } else {
                self = .suppressed
            }
        }
    }

    /// Whether the suggestion's location is in production code or a test target.
    public enum Site: String, Codable, CaseIterable, Sendable {
        /// A production target's file.
        case production
        /// A test target's file: a law lifted from a test.
        case test
    }

    /// How a property test checking the suggestion was found.
    public enum TestLink: String, Codable, CaseIterable, Sendable {
        /// A test file's leading comments carry its identity, as the files
        /// SwiftInferProperties generates do; exact.
        case generated
        /// A property test outside generated files, in a test target that
        /// depends on the function's module, directly or not, calls the
        /// function or its partner by base name; a heuristic.
        case handwritten
        /// `@CheckProperty` on the function or its partner expands into a
        /// property test.
        case macro
    }

    /// Why a suggestion attaches to no function record.
    public enum Unmapped: String, Codable, CaseIterable, Sendable {
        /// A scanned file, outside any function or type.
        case file
        /// No usable location: `(unknown)`, `<corpus>:0`, or a path
        /// outside the package.
        case missingLocation = "noLocation"
        /// Inside a type, outside any function: a protocol requirement,
        /// for one.
        case type
        /// A file SwiftStats didn't scan.
        case unscanned
    }

    /// What verify evidence says of the code as it is.
    public struct Judgement: Codable, Hashable, Sendable {
        /// Whether the evidence was measured on the code as it is: the
        /// record's and the row's subject fingerprints are both present and
        /// equal. False when no record names the suggestion.
        public let fresh: Bool
        /// Whether fresh `measured-bothPass` evidence lifts the suggestion
        /// to Verified, as SwiftInferProperties' own rule does: a tier other
        /// than Advisory, and a score that reaches the Strong band with 50 added.
        public let verified: Bool
        /// Whether fresh `measured-defaultFails` evidence disproves the law.
        public let disproven: Bool

        /// Creates a judgement. Fields are documented on their properties.
        public init(fresh: Bool, verified: Bool, disproven: Bool) {
            self.fresh = fresh
            self.verified = verified
            self.disproven = disproven
        }
    }

    /// The package's verify evidence for a suggestion, from
    /// `.swiftinfer/verify-evidence.json`.
    public struct Verification: Codable, Hashable, Sendable {
        /// The evidence's outcome; nil when no record names the suggestion.
        public let outcome: VerifyOutcome?
        /// What the evidence says of the code as it is; nil when that can't
        /// be decided: a record names an interaction row, which carries no
        /// subject fingerprint in the index (SwiftInferProperties computes
        /// it apart), so freshness can't be checked.
        public let judgement: Judgement?

        /// Creates a verify join. Fields are documented on their properties.
        public init(outcome: VerifyOutcome?, judgement: Judgement?) {
            self.outcome = outcome
            self.judgement = judgement
        }
    }

    /// A verify run's outcome, as `verify-evidence.json` writes it.
    public enum VerifyOutcome: String, Codable, CaseIterable, Sendable {
        /// No verify run could cover the law yet.
        case architecturalCoveragePending = "architectural-coverage-pending"
        /// Both the default and the edge-case domains passed.
        case measuredBothPass = "measured-bothPass"
        /// The default domain found a counterexample.
        case measuredDefaultFails = "measured-defaultFails"
        /// Only a curated edge case found a counterexample.
        case measuredEdgeCaseAdvisory = "measured-edgeCaseAdvisory"
        /// The run failed.
        case measuredError = "measured-error"
    }

    /// SwiftInferProperties' identity hash, `0x` and 16 uppercase hex digits.
    public let identity: String
    /// Which list it comes from.
    public let population: Population
    /// The template (`idempotence`, `round-trip`, …), or an interaction
    /// row's family.
    public let template: String
    /// The tier as written (`Strong`, `Likely`, `Possible`, `Advisory`).
    public let tier: String
    /// The summed signal weights, kept on Advisory rows too.
    public let score: Int
    /// The band of `score`.
    public let scoreBand: ScoreBand
    /// Whether a structural blocker says no test can run the law as written.
    public let blocked: Bool
    /// The function as SwiftInferProperties names it (`normalized(_:)`), or
    /// an interaction row's reducer.
    public let function: String
    /// The declaring type's lexical path, when the row names one.
    public let typeName: String?
    /// Where it is and what it attaches to; nil when the row has no usable location.
    public let location: FindingLocation?
    /// Whether the location is in production code or a test target; nil
    /// when it is in no scanned file.
    public let site: Site?
    /// Why it attaches to no function; nil when it does.
    public let unmapped: Unmapped?
    /// Whether its file is generated (PRD D8).
    public let generated: Bool
    /// Whether targets found the identity at more than one location, so
    /// each location is a candidate of its own.
    public let identityCollision: Bool
    /// The second function of a round-trip, differential-equivalence or
    /// emptiness-agreement row, as SwiftInferProperties names it.
    public let partner: String?
    /// The partner's record: a function or getter of that base name in the
    /// primary's file and type; nil when there is none.
    public let partnerKey: String?
    /// The package's decision on it; nil when the decisions file for its
    /// population is absent or has no record of it.
    public internal(set) var decision: Decision?
    /// The package's verify evidence; nil when
    /// `.swiftinfer/verify-evidence.json` is absent or unreadable.
    public internal(set) var verification: Verification?
    /// How a property test checking it was found; nil when none was.
    public internal(set) var testedBy: TestLink?
    /// The linking tests' keys, sorted: those in its generated file, or the
    /// property tests calling it; empty for a macro link or none.
    public internal(set) var testKeys: [String] = []

    /// Creates a candidate. Fields are documented on their properties.
    public init(
        identity: String,
        population: Population,
        template: String,
        tier: String,
        score: Int,
        blocked: Bool,
        function: String,
        typeName: String?,
        location: FindingLocation?,
        site: Site?,
        unmapped: Unmapped?,
        generated: Bool,
        identityCollision: Bool,
        partner: String?,
        partnerKey: String?
    ) {
        self.identity = identity
        self.population = population
        self.template = template
        self.tier = tier
        self.score = score
        scoreBand = ScoreBand(score: score)
        self.blocked = blocked
        self.function = function
        self.typeName = typeName
        self.location = location
        self.site = site
        self.unmapped = unmapped
        self.generated = generated
        self.identityCollision = identityCollision
        self.partner = partner
        self.partnerKey = partnerKey
    }
}
