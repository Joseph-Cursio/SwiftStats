//
//  CloneClass.swift
//  SwiftStatsCore
//
//  One clone class of SwiftCloneDetector (PRD §7.12), after SwiftStats
//  merges the tool's passes as the tool's own `--all` does: which pass
//  found it, whether its copies are token-identical, its size, and its
//  copies attached to function records.
//

/// A set of copies of one piece of code.
public struct CloneClass: Codable, Hashable, Sendable {
    /// The detector pass that reported the class.
    public enum Pass: String, Codable, CaseIterable, Sendable {
        /// Fragments alike in shape, not identical (`--type3`).
        case nearMiss = "near-miss"
        /// A run of two or more identical sibling statements or members
        /// (`--sequence`).
        case sequence
        /// One syntax node copied, identifiers and literals possibly
        /// renamed (the default pass).
        case subtree

        /// The passes from the strongest claim to the weakest: identical,
        /// a run of identical statements, then alike.
        static let bySpecificity: [Self] = [.subtree, .sequence, .nearMiss]

        /// How precise the pass's claim is, lower first; the merge never
        /// lets a weaker claim hide a stronger one.
        var specificity: Int {
            Self.bySpecificity.firstIndex(of: self) ?? Self.bySpecificity.count
        }
    }

    /// The class's number, from 1, in the order of its first copy, then
    /// pass, then mass, largest first.
    public let ordinal: Int
    /// The pass that reported it.
    public let pass: Pass
    /// Whether a subtree class's copies are token-identical: its copies are
    /// exactly a `--type1` class's. False for renamed copies and for other
    /// passes.
    public let exact: Bool
    /// The tool's mass: syntax nodes plus tokens; for near-miss, the
    /// largest copy's; for a sequence, the run's sum.
    public let mass: Int
    /// For near-miss, the least similarity between two copies, to four
    /// places; nil for other passes.
    public let similarity: Double?
    /// The tool's line span, of the copy it lists first.
    public let lineSpan: Int
    /// The tool's fingerprint: a hint across snapshots, never an identity.
    public let fingerprint: String
    /// The copies, in file and position order.
    public let instances: [CloneInstance]

    /// Creates a class. Fields are documented on their properties.
    public init(
        ordinal: Int,
        pass: Pass,
        exact: Bool,
        mass: Int,
        similarity: Double?,
        lineSpan: Int,
        fingerprint: String,
        instances: [CloneInstance]
    ) {
        self.ordinal = ordinal
        self.pass = pass
        self.exact = exact
        self.mass = mass
        self.similarity = similarity
        self.lineSpan = lineSpan
        self.fingerprint = fingerprint
        self.instances = instances
    }
}
