//
//  RequestedTiers.swift
//  SwiftStatsCore
//
//  The slow collectors a scan runs only when asked for (M5, M6): coverage
//  (`scan --coverage`) and mutation (`scan --mutation`, with `--since` or
//  `--resume`). `backfill` and `diff`'s scans of other revisions ask for
//  neither. The flags' combinations are checked here, so every front end
//  refuses the same ones with the same words.
//

/// Which of the opt-in collectors a scan runs.
public struct RequestedTiers: Hashable, Sendable {
    /// Why `scan`'s flags can't be combined as given; the message is the
    /// whole explanation, for the command line's usage error.
    public struct FlagConflict: Error, Equatable, CustomStringConvertible {
        /// What is wrong with the flags.
        public let message: String

        /// The explanation the command line prints.
        public var description: String {
            message
        }
    }

    /// Neither: the scan runs only the collectors that always run.
    public static let syntaxOnly = Self()
    /// Coverage alone, as `scan --coverage` asks for it.
    public static let coverage = Self(coverage: true)

    /// Whether the coverage collector runs (`scan --coverage`).
    public let coverage: Bool
    /// Which SwiftMutator run the scan asked for; nil when it didn't
    /// (`scan` without `--mutation`).
    public let mutation: MutationRequest?

    /// Tiers. Fields are documented on their properties.
    public init(coverage: Bool = false, mutation: MutationRequest? = nil) {
        self.coverage = coverage
        self.mutation = mutation
    }

    /// The tiers `scan`'s flags ask for: `--coverage`, `--mutation`,
    /// `--since <rev>` and `--resume`, where `storing` is false for
    /// `--no-store`. Throws when `--since` or `--resume` comes without
    /// `--mutation`, when both come together (a resume takes its base from
    /// the run it continues), when `--since` names nothing, or when either
    /// comes with `--no-store`, since both read the store.
    public static func scanFlags(
        coverage: Bool,
        mutation: Bool,
        since: String?,
        resume: Bool,
        storing: Bool
    ) throws(FlagConflict) -> Self {
        if since != nil, mutation == false {
            throw FlagConflict(message: "--since needs --mutation")
        }
        if resume, mutation == false {
            throw FlagConflict(message: "--resume needs --mutation")
        }
        if since != nil, resume {
            throw FlagConflict(
                message: "give --since or --resume, not both; a resume keeps the base of the run it continues"
            )
        }
        if let since, since.isEmpty {
            throw FlagConflict(message: "--since needs a commit, branch or tag")
        }
        if storing == false, since != nil || resume {
            let flag = resume ? "--resume" : "--since"
            throw FlagConflict(message: "\(flag) reads the snapshot store, so it can't be used with --no-store")
        }
        guard mutation else {
            return Self(coverage: coverage)
        }
        if resume {
            return Self(coverage: coverage, mutation: .resume)
        }
        return Self(coverage: coverage, mutation: since.map(MutationRequest.since) ?? .full)
    }
}
