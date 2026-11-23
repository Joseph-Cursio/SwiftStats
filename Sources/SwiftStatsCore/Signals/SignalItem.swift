//
//  SignalItem.swift
//  SwiftStatsCore
//
//  One item in a signal's ranking: what it is about (a function family, a
//  type, a clone copy), where, its score, and the inputs its score came
//  from, so a reader can see why it is there. The inputs come as payloads,
//  one per kind of input; an item carries the payloads its signal fills
//  and omits the rest. Report schema 3 and top schema 2 (M4) name the
//  subject `subject` (it was `family`) and move M3's inputs into `history`;
//  report schema 4 and top schema 3 (M5) add `markers`, `coverage` and a
//  clone class's `coverage` (M5's payloads are in `SignalItem+Coverage.swift`);
//  M6 adds `mutation` and `ratio` (in `SignalItem+Mutation.swift`).
//

/// An item's place in a signal.
public struct SignalItem: Codable, Hashable, Sendable {
    /// What a history signal scores: the family's history in the window.
    public struct History: Codable, Hashable, Sendable {
        /// Commits in the window that changed it, sweeps aside.
        public let changes: Int
        /// Its cognitive complexity (a property's: its most complex accessor's).
        public let cognitive: Int?
        /// Fix commits in the window.
        public let fixes: Int
        /// Fix commits ever.
        public let allFixes: Int
        /// Fixes weighted by age.
        public let fixScore: Double
        /// Reverts in the window.
        public let reverts: Int
        /// Repeated fixes in the window.
        public let repeatedFixes: Int
        /// Changes in the window that changed a matching test too.
        public let testChanges: Int
        /// When it first appeared.
        public let firstSeen: String?
        /// How surely its history was traced.
        public let tracedBy: TracedBy
    }

    /// The SwiftInferProperties suggestion an item is about.
    public struct Property: Codable, Hashable, Sendable {
        /// The suggestion's identity hash, as written.
        public let identity: String
        /// Its template, such as `idempotence`.
        public let template: String
        /// Its tier, as written.
        public let tier: String
        /// Its score.
        public let score: Int
        /// Whether fresh verify evidence lifts it to Verified.
        public let verified: Bool
        /// Whether a structural blocker holds it at Advisory.
        public let blocked: Bool
        /// What the package's decisions file records; nil when nothing.
        public let decision: PropertyCandidate.Decision?
        /// The second function a two-function law names; nil for one.
        public let partner: String?
        /// How a property test checking it was found; nil when none was.
        public let testedBy: PropertyCandidate.TestLink?
    }

    /// What SwiftEffectInference says of an item's function.
    public struct Effect: Codable, Hashable, Sendable {
        /// The tier body inference gives the function, with its anchor,
        /// depth and the calls that gave it, as a scan writes them; nil
        /// when the body gives no tier.
        public let inferred: EffectFacts.Inferred?
        /// The purity verdict.
        public let purity: EffectFacts.Purity
        /// Where the resolved tier comes from.
        public let source: EffectFacts.Source
        /// The algebraic shape of a value-shaped function's signature; nil
        /// when it has none, or the signal doesn't read it.
        public let shape: EffectFacts.Shape?
    }

    /// The size of an item's function, for a signal that shows it.
    public struct Function: Codable, Hashable, Sendable {
        /// Lines in its body.
        public let bodyLines: Int
        /// Its cognitive complexity; nil when it wasn't computed.
        public let cognitive: Int?
    }

    /// The law-check pairs an item's type leaves unchecked.
    public struct Laws: Codable, Hashable, Sendable {
        /// The protocols, sorted.
        public let protocols: [String]
        /// Whether the package depends on SwiftPropertyLaws.
        public let kitDependency: Bool
    }

    /// The clone class an item is about.
    public struct Clone: Codable, Hashable, Sendable {
        /// The class's ordinal in its snapshot: for divergent clones, the
        /// earlier snapshot.
        public let ordinal: Int
        /// The run that found it.
        public let pass: CloneClass.Pass
        /// Whether a subtree class's copies are token for token the same.
        public let exact: Bool
        /// Its mass, as the tool counts it.
        public let mass: Int
        /// Its stripped lines: for divergent clones, those of the units
        /// in its diverging slots, which the score counts; for a hotspot,
        /// those its copies cover; for uneven clone testing, those of its
        /// copies at most 20% covered.
        public let lines: Int
        /// Its copies: for divergent clones, those with a production family
        /// outside generated files now.
        public let copies: Int
        /// Distinct commits in the window that changed its families; nil
        /// when the signal doesn't count them.
        public let churn: Int?
        /// How its copies changed since an earlier snapshot; nil when the
        /// signal doesn't compare one. Nested, not flat, so that a signal
        /// comparing none writes no empty copy lists.
        public let divergence: Divergence?
        /// How well the tests cover its copies; nil when the signal doesn't
        /// read coverage.
        public let coverage: CloneCoverage?
    }

    /// How a clone class's copies changed since an earlier snapshot.
    public struct Divergence: Codable, Hashable, Sendable {
        /// The earlier snapshot's commit.
        public let sinceCommit: String
        /// The earlier snapshot's ordinals of the classes folded into this item.
        public let folded: [Int]
        /// The copies changed since then.
        public let changed: [CloneCopy]
        /// The copies unchanged since then.
        public let unchanged: [CloneCopy]
    }

    /// One copy of a clone class, as the family now holding it.
    public struct CloneCopy: Codable, Hashable, Sendable {
        /// The family's id.
        public let family: String
        /// Its file.
        public let file: String
        /// Where it starts.
        public let line: Int
        /// Commits since the earlier snapshot that changed it, sweeps aside.
        public let changes: Int
        /// When the latest of those commits was made, written as a
        /// family's `firstSeen` is; nil when there are none.
        public let lastChange: String?
    }

    /// An item before it is ranked: what a signal's scorer gives, with
    /// the payloads its signal fills.
    struct Draft: Hashable, Sendable {
        /// What the item is about: a family's id, or a type as `Module::Name`.
        let subject: String
        /// Its file.
        let file: String
        /// Where it starts.
        let line: Int
        /// History's inputs.
        var history: History?
        /// The suggestion.
        var property: Property?
        /// SwiftEffectInference's facts.
        var effect: Effect?
        /// The function's size.
        var function: Function?
        /// The unchecked law pairs.
        var laws: Laws?
        /// The clone class.
        var clone: Clone?
        /// The markers.
        var markers: Markers?
        /// The subject's coverage.
        var coverage: Coverage?
        /// The function's mutation results.
        var mutation: Mutation?
        /// The module's and the project's test-to-code line ratio.
        var ratio: Ratio?
    }

    /// Its position, from 1.
    public let rank: Int
    /// What it is about: a family's id, or a type as `Module::Name`.
    public let subject: String
    /// Its file.
    public let file: String
    /// Where it starts.
    public let line: Int
    /// Its score.
    public let score: Double
    /// Whether it is a member of the signal, not only ranked.
    public let member: Bool
    /// History's inputs, for a history signal.
    public let history: History?
    /// The suggestion, for a signal about one.
    public let property: Property?
    /// SwiftEffectInference's facts, for a signal reading them.
    public let effect: Effect?
    /// The function's size, for a signal showing it.
    public let function: Function?
    /// The unchecked law pairs, for a signal about them.
    public let laws: Laws?
    /// The clone class, for a clone signal.
    public let clone: Clone?
    /// The markers, for a signal about them.
    public let markers: Markers?
    /// The subject's coverage, for a signal reading it.
    public let coverage: Coverage?
    /// The function's mutation results, for a signal reading them.
    public let mutation: Mutation?
    /// The module's and the project's test-to-code line ratio, for a
    /// signal reading it.
    public let ratio: Ratio?

    /// `draft` ranked at `rank` with `score`, a member or not.
    init(_ draft: Draft, rank: Int, score: Double, member: Bool) {
        self.rank = rank
        subject = draft.subject
        file = draft.file
        line = draft.line
        self.score = score
        self.member = member
        history = draft.history
        property = draft.property
        effect = draft.effect
        function = draft.function
        laws = draft.laws
        clone = draft.clone
        markers = draft.markers
        coverage = draft.coverage
        mutation = draft.mutation
        ratio = draft.ratio
    }
}
