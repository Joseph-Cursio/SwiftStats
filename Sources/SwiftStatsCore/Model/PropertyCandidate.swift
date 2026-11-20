//
//  PropertyCandidate.swift
//  SwiftStatsCore
//
//  One property-test suggestion of SwiftInferProperties (PRD §7.11): a
//  row of `swift-infer index`, merged over the package's targets and
//  attached to the function record it names, or listed as unmapped.
//

/// A property-test suggestion and where it attaches.
public struct PropertyCandidate: Codable, Hashable, Sendable {
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
