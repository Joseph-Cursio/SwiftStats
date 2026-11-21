//
//  SignalItem+Coverage.swift
//  SwiftStatsCore
//
//  The payloads M5's signals fill (report schema 4, top schema 3): the
//  risk markers an item holds and how many no test ran, its subject's
//  coverage, and how well the tests cover each copy of a clone class.
//

public extension SignalItem {
    /// The risk markers an item's subject holds (risky + untested).
    struct Markers: Codable, Hashable, Sendable {
        /// Per rule, the untested markers and all markers, as
        /// `[untested, total]`.
        public let byRule: [String: [Int]]
        /// Markers on lines that ran while holding a region that didn't (an
        /// unrun branch, closure or autoclosure), counted as tested.
        public let onPartlyRunLines: Int
    }

    /// The coverage of an item's subject: a function's own, or the sum
    /// over a type's member functions and the coverage attached to it, or
    /// over what is attached to a file.
    struct Coverage: Codable, Hashable, Sendable {
        /// Its lines; nil when nothing of it has coverage data.
        public let lines: CoverageTally?
        /// Its code regions; nil when nothing of it has coverage data.
        public let regions: CoverageTally?
    }

    /// How well the tests cover a clone class's copies (uneven clone testing).
    struct CloneCoverage: Codable, Hashable, Sendable {
        /// The ordinals of the classes folded into this item, sorted.
        public let folded: [Int]
        /// The copies with a mapped line, in the class's order.
        public let copies: [CoveredCopy]
    }

    /// One clone copy with its line coverage.
    struct CoveredCopy: Codable, Hashable, Sendable {
        /// Its file.
        public let file: String
        /// Where it starts.
        public let line: Int
        /// The family holding it, by M4's copy-to-family rule: the first
        /// family it covers whole, else its containing record's family;
        /// `<file>:<line>` when neither exists.
        public let family: String
        /// Its mapped lines that ran.
        public let covered: Int
        /// Its mapped lines: lines in its range the file's line data counts.
        public let mapped: Int
    }
}
