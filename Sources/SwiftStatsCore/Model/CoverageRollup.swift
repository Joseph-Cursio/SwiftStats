//
//  CoverageRollup.swift
//  SwiftStatsCore
//
//  Coverage summed over a production module or the project's production
//  part (M5, PRD §7.8): lines from each kept file's line data, regions from
//  the records' and attachments' regions, the records with and without
//  coverage data, and the public functions by how their tests are linked
//  (a heuristic). The project's part also counts the unmapped entries and
//  the coverage attached to types and files. Absent when the coverage
//  collector didn't run, and from test modules and the `tests` part; lines
//  and regions null for a scope no test bundle links, never 0 of 0.
//

/// Coverage counted over one production scope.
public struct CoverageRollup: Codable, Hashable, Sendable {
    /// Covered of total, with the percentage.
    public struct Share: Codable, Hashable, Sendable {
        /// Percentages are out of this.
        private static let wholePercent = 100.0
        /// Percentages keep this many hundredths: two decimal places.
        private static let hundredths = 100.0

        /// How many ran at least once.
        public let covered: Int
        /// How many there are.
        public let total: Int
        /// `covered` as a percentage of `total`, to two decimal places;
        /// nil when there are none.
        public let percent: Double?

        /// The share of `covered` in `total`.
        init(covered: Int, total: Int) {
            self.covered = covered
            self.total = total
            percent = Self.percent(covered: covered, total: total)
        }

        /// `covered` as a percentage of `total`, rounded to two decimal
        /// places; nil when `total` is 0: a share of nothing is not 0%.
        static func percent(covered: Int, total: Int) -> Double? {
            guard total > 0 else {
                return nil
            }
            return (Double(covered) * wholePercent * hundredths / Double(total)).rounded() / hundredths
        }
    }

    /// The scope's function records by coverage data.
    public struct Functions: Codable, Hashable, Sendable {
        /// Records with coverage data.
        public let withData: Int
        /// Records with coverage data that ran: a region of theirs has a
        /// count above 0.
        public let executed: Int
        /// Records with no coverage data and a reason for it (subscripts
        /// whose accessors carry the coverage are in neither count).
        public let noData: Int
    }

    /// The scope's public functions by how their tests are linked (a
    /// heuristic: the test's target ran it and its body names it).
    public struct PublicFunctions: Codable, Hashable, Sendable {
        /// Public functions: production, non-generated `public` or `open`
        /// functions, initialisers and accessors, and subscripts that are
        /// no containers.
        public let total: Int
        /// Those with coverage data: `linked + unlinked + reachedGenerically`.
        public let withCoverage: Int
        /// Those with coverage data that one test or more links.
        public let linked: Int
        /// Those with coverage data that no test links.
        public let unlinked: Int
        /// Witnesses of standard protocols' requirements with coverage
        /// data, which tests reach generically: neither linked nor unlinked.
        public let reachedGenerically: Int
        /// Protocol extension members with coverage data, linked by their
        /// base name alone, the weaker rule; counted again within `linked`
        /// and `unlinked`.
        public let extensionMembers: Int
        /// The linked tests of the public functions that have a count:
        /// those with coverage data, witnesses left out.
        public let linkedTests: Distribution
    }

    /// The coverage outside every function record, over the project.
    public struct Attached: Codable, Hashable, Sendable {
        /// Types and files with coverage attached.
        public let owners: Int
        /// Their lines.
        public let lines: Share
        /// Their regions.
        public let regions: Share
    }

    /// Mapped lines of the scope's kept files, by llvm-cov's file line
    /// rule; a partly run line counts as covered. Nil when no file of the
    /// scope is in the export: nothing measured it, which is not 0 of 0.
    public let lines: Share?
    /// Code regions of the scope's records and attachments. Nil when none
    /// of them has regions: nothing measured the scope.
    public let regions: Share?
    /// The scope's records by coverage data.
    public let functions: Functions
    /// The scope's public functions by their tests.
    public let publicFunctions: PublicFunctions
    /// Export entries in production files that nothing took; on the
    /// project's production part only.
    public let unmapped: Int?
    /// Coverage attached to types and files; on the project's production
    /// part only.
    public let attached: Attached?
}
