//
//  MutationRollup.swift
//  SwiftStatsCore
//
//  Mutation results summed over a production module or the project's
//  production part (M6, design §4): every mapped mutant of the scope, its
//  records' and its attachments' alike, counted by verdict, with
//  SwiftMutator's score over them, how many were carried from an earlier
//  snapshot, and the production functions outside generated files by
//  their mutation state. The project's part also counts the unmapped and
//  dropped mutants. The score is SwiftStats' aggregation (SwiftMutator
//  scores files only); its percentage is null when the results are
//  incomplete, the counts kept. Absent when the collector left no
//  results, and from test modules and the `tests` part. The scan JSON
//  writes the counts beside the other fields, so their metric names are
//  `mutation.killed` and so on.
//

/// Mutation results counted over one production scope.
public struct MutationRollup: Codable, Hashable, Sendable {
    /// The scope's production functions outside generated files, by
    /// mutation state.
    public struct Functions: Codable, Hashable, Sendable {
        /// Functions with a mutant killed, survived, with no coverage or
        /// timed out.
        public let scored: Int
        /// Functions with only not-covered mutants.
        public let notCoveredOnly: Int
        /// Functions with only build errors.
        public let buildErrorsOnly: Int
        /// Functions with no mutant.
        public let noMutant: Int
        /// Functions in unresolved files, with no results.
        public let noResults: Int
        /// Functions in unlisted files.
        public let notListed: Int

        /// The functions in `states` counted by state.
        init(_ states: [MutationFunctionState]) {
            scored = states.count { $0 == .scored }
            notCoveredOnly = states.count { $0 == .notCoveredOnly }
            buildErrorsOnly = states.count { $0 == .buildErrorsOnly }
            noMutant = states.count { $0 == .noMutant }
            noResults = states.count { $0 == .noResults }
            notListed = states.count { $0 == .notListed }
        }
    }

    /// The keys the scan JSON writes beside the counts.
    private enum CodingKeys: String, CodingKey {
        case score
        case carried
        case functions
        case unmapped
        case dropped
    }

    /// The scope's mapped mutants by verdict.
    public let counts: MutationCounts
    /// SwiftMutator's score over them; its percentage nil when the results
    /// are incomplete.
    public let score: MutationScore
    /// How many of them were carried from an earlier snapshot.
    public let carried: Int
    /// The scope's functions by state.
    public let functions: Functions
    /// Mutants in production files the mapping couldn't use; on the
    /// project's production part only.
    public let unmapped: Int?
    /// Mutants dropped by design; on the project's production part only.
    public let dropped: Int?

    /// Creates a roll-up. Fields are documented on their properties.
    init(
        counts: MutationCounts,
        score: MutationScore,
        carried: Int,
        functions: Functions,
        unmapped: Int?,
        dropped: Int?
    ) {
        self.counts = counts
        self.score = score
        self.carried = carried
        self.functions = functions
        self.unmapped = unmapped
        self.dropped = dropped
    }

    /// Reads the roll-up, its counts beside its fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(MutationScore.self, forKey: .score)
        carried = try container.decode(Int.self, forKey: .carried)
        functions = try container.decode(Functions.self, forKey: .functions)
        unmapped = try container.decodeIfPresent(Int.self, forKey: .unmapped)
        dropped = try container.decodeIfPresent(Int.self, forKey: .dropped)
        counts = try MutationCounts(from: decoder)
    }

    /// Writes the roll-up, its counts beside its fields, leaving out what
    /// only the project's part has.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(score, forKey: .score)
        try container.encode(carried, forKey: .carried)
        try container.encode(functions, forKey: .functions)
        try container.encodeIfPresent(unmapped, forKey: .unmapped)
        try container.encodeIfPresent(dropped, forKey: .dropped)
        try counts.encode(to: encoder)
    }
}
