//
//  SignalThresholds.swift
//  SwiftStatsCore
//
//  `signals:` in `.swiftstats.yml` (PRD §8, §10.1): the share of candidates
//  a ranked signal keeps, the absolute limits of M6's mutation signals
//  (design §7): a percent of lines covered or of mutants killed, a fewest
//  number of scored mutants, or, for genuinely under-tested, an optional
//  test-to-code line ratio, unset by default; and hidden coupling's (M7,
//  design §8): the fewest commits changing both families and the least
//  confidence, a percent. Read when a report is made, so they can be tuned
//  without rescanning; reports print the thresholds they used.
//

/// The membership thresholds of the ranked signals and the limits of the
/// mutation signals and hidden coupling.
public struct SignalThresholds: Hashable, Sendable {
    /// What a signal's limit is, which says what it may be set to.
    enum LimitKind: Hashable, Sendable {
        /// A percent, 0 to 100.
        case percent
        /// A whole number from 1 to a million.
        case count
        /// A ratio above 0.
        case ratio
    }

    /// The signals that take a threshold.
    static let rankedSignals: Set<String> = ["hotspot", "bug-prone", "clone-hotspot"]
    /// The default percent of candidates a ranked signal keeps.
    public static let defaultPercent = 10.0
    /// The weak tests signal's name in `signals:`.
    static let weakTests = "weak-tests"
    /// The genuinely under-tested signal's name in `signals:`.
    static let genuinelyUnderTested = "genuinely-under-tested"
    /// The uneven clone testing (mutation) signal's name in `signals:`.
    static let unevenCloneMutation = "uneven-clone-mutation"
    /// The hidden coupling signal's name in `signals:`.
    static let hiddenCoupling = "hidden-coupling"
    /// The limit of line coverage.
    static let coverage = "coverage"
    /// The limit of the function score.
    static let score = "score"
    /// The fewest scored mutants.
    static let mutants = "mutants"
    /// Genuinely under-tested's optional test-to-code line ratio.
    static let ratio = "ratio"
    /// Uneven clone mutation's least function score of a well tested copy.
    static let high = "high"
    /// Uneven clone mutation's greatest function score of a poorly tested copy.
    static let low = "low"
    /// Hidden coupling's fewest commits in the window changing both families.
    static let support = "support"
    /// Hidden coupling's least support as a percent of the less-changed
    /// family's changes.
    static let confidence = "confidence"
    /// The limits each signal taking limits takes, by signal, then limit.
    static let limitKinds: [String: [String: LimitKind]] = [
        weakTests: [coverage: .percent, score: .percent, mutants: .count],
        genuinelyUnderTested: [coverage: .percent, score: .percent, mutants: .count, ratio: .ratio],
        unevenCloneMutation: [high: .percent, low: .percent, mutants: .count],
        hiddenCoupling: [support: .count, confidence: .percent]
    ]
    /// Weak tests' least line coverage, in percent, by default.
    private static let weakCoverage = 80.0
    /// Weak tests' function score to fall below, in percent, by default.
    private static let weakScore = 50.0
    /// Genuinely under-tested's greatest line coverage, in percent, by default.
    private static let underTestedCoverage = 20.0
    /// Genuinely under-tested's function score to fall below, in percent, by default.
    private static let underTestedScore = 20.0
    /// The per-function signals' fewest scored mutants by default.
    private static let functionMutants = 3.0
    /// Uneven clone mutation's least function score of a well tested copy, by default.
    private static let cloneHigh = 80.0
    /// Uneven clone mutation's greatest function score of a poorly tested copy, by default.
    private static let cloneLow = 20.0
    /// Uneven clone mutation's fewest scored mutants per copy by default.
    private static let copyMutants = 2.0
    /// Hidden coupling's fewest commits changing both families by default.
    private static let couplingSupport = 3.0
    /// Hidden coupling's least confidence, in percent, by default.
    private static let couplingConfidence = 50.0
    /// Each limit-taking signal's limits when the configuration sets none,
    /// by signal, then limit; genuinely under-tested's ratio has none.
    static let defaultLimits: [String: [String: Double]] = [
        weakTests: [coverage: weakCoverage, score: weakScore, mutants: functionMutants],
        genuinelyUnderTested: [coverage: underTestedCoverage, score: underTestedScore, mutants: functionMutants],
        unevenCloneMutation: [high: cloneHigh, low: cloneLow, mutants: copyMutants],
        hiddenCoupling: [support: couplingSupport, confidence: couplingConfidence]
    ]

    /// Percent of candidates kept, by signal name; absent means the default.
    public let percents: [String: Double]
    /// The mutation signals' and hidden coupling's limits the
    /// configuration sets, by signal name, then limit; absent means the
    /// default.
    public let limits: [String: [String: Double]]

    /// Thresholds. Fields are documented on their properties.
    public init(percents: [String: Double] = [:], limits: [String: [String: Double]] = [:]) {
        self.percents = percents
        self.limits = limits
    }

    /// The percent of candidates `signal` keeps.
    public func percent(for signal: String) -> Double {
        percents[signal] ?? Self.defaultPercent
    }

    /// The limit `name` of the signal `signal`: as set, else the default;
    /// nil when neither (genuinely under-tested's ratio unset).
    public func limit(_ name: String, of signal: String) -> Double? {
        limits[signal]?[name] ?? Self.defaultLimits[signal]?[name]
    }
}
