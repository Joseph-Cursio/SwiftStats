//
//  CloneDetectorOutput.swift
//  SwiftStatsCore
//
//  `swift-clone-detector --format json` as SwiftStats reads it (PRD
//  §7.12). The tool writes no schema version, so the `tool` field is
//  checked instead; `similarity` is absent, not null, outside near-miss
//  runs; an instance's end column is exclusive.
//

/// One run's JSON report.
struct CloneDetectorOutput: Decodable, Sendable {
    /// One copy as the tool writes it; ordered by path, then start and
    /// end line and column, as the tool orders copies when it merges.
    struct Instance: Decodable, Hashable, Comparable, Sendable {
        /// The path as given to the tool.
        let path: String
        /// 1-based first line.
        let startLine: Int
        /// 1-based UTF-8 column of the first character.
        let startColumn: Int
        /// 1-based last line.
        let endLine: Int
        /// 1-based UTF-8 column just after the last character.
        let endColumn: Int

        /// Why these positions can't be a copy's: one below 1, or an end
        /// before the start; nil when they can.
        var malformation: String? {
            if [startLine, startColumn, endLine, endColumn].contains(where: { $0 < 1 }) {
                return "has a position below 1"
            }
            if (startLine, startColumn) > (endLine, endColumn) {
                return "ends before it starts"
            }
            return nil
        }

        /// Path order, then position order.
        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.path != rhs.path {
                return lhs.path < rhs.path
            }
            return [lhs.startLine, lhs.startColumn, lhs.endLine, lhs.endColumn]
                .lexicographicallyPrecedes([rhs.startLine, rhs.startColumn, rhs.endLine, rhs.endColumn])
        }
    }

    /// One clone class as the tool writes it.
    struct Clone: Decodable, Sendable {
        /// The tool's fingerprint.
        let fingerprint: String
        /// Syntax nodes plus tokens.
        let mass: Int
        /// The first listed copy's line span.
        let lineSpan: Int
        /// The least pairwise similarity, near-miss only.
        let similarity: Double?
        /// The copies, in the tool's order.
        let instances: [Instance]
    }

    /// The tool's name, `swift-clone-detector`.
    let tool: String
    /// The tool's version string.
    let version: String
    /// The tool's duplicated-line count.
    let duplicatedLines: Int
    /// The classes, in the tool's order.
    let clones: [Clone]
}
