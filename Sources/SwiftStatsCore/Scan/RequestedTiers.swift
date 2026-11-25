//
//  RequestedTiers.swift
//  SwiftStatsCore
//
//  The slow collectors a scan runs only when asked for (M5–M7): coverage
//  (`scan --coverage`), mutation (`scan --mutation`, with `--since` or
//  `--resume`) and the T1 group (`scan --index`: the build, the index read
//  and outskirts). `backfill` and `diff`'s scans of other revisions ask
//  for none of them. The flags' combinations are checked here, so every
//  front end refuses the same ones with the same words. A `--since` run,
//  or the resume of one, also carries the stored snapshot it merges with,
//  which the scan chooses before anything runs (M6, design §6.1).
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

    /// None: the scan runs only the collectors that always run.
    public static let syntaxOnly = Self()
    /// Coverage alone, as `scan --coverage` asks for it.
    public static let coverage = Self(coverage: true)

    /// Whether the coverage collector runs (`scan --coverage`).
    public let coverage: Bool
    /// Which SwiftMutator run the scan asked for; nil when it didn't
    /// (`scan` without `--mutation`).
    public let mutation: MutationRequest?
    /// Whether the T1 group runs (`scan --index`): the `build`, `index`
    /// and `periphery` collectors.
    public let index: Bool
    /// The stored snapshot a `--since` run, or the resume of one, merges
    /// with, chosen before the scan; nil until chosen, and for other runs.
    let base: MutationBase?

    /// Tiers. Fields are documented on their properties.
    public init(coverage: Bool = false, mutation: MutationRequest? = nil, index: Bool = false) {
        self.coverage = coverage
        self.mutation = mutation
        self.index = index
        base = nil
    }

    /// Tiers asking for `coverage`, `mutation` and `index`, merging with
    /// `base`.
    private init(coverage: Bool, mutation: MutationRequest?, index: Bool, base: MutationBase?) {
        self.coverage = coverage
        self.mutation = mutation
        self.index = index
        self.base = base
    }

    /// The tiers `scan`'s flags ask for: `--coverage`, `--mutation`,
    /// `--since <rev>` and `--resume`, where `storing` is false for
    /// `--no-store`. Throws when `--since` or `--resume` comes without
    /// `--mutation`, when both come together (a resume takes its base from
    /// the run it continues), when `--since` names nothing, or when either
    /// comes with `--no-store`, since both read the store. `--index`
    /// combines with every flag, so `asking(index:)` adds it.
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

    /// The same tiers, asking for the T1 group when `index` is true
    /// (`scan --index`, which combines with every other flag).
    public func asking(index: Bool) -> Self {
        Self(coverage: coverage, mutation: mutation, index: index, base: base)
    }

    /// The same tiers, the SwiftMutator run merging with `chosen`.
    func merging(with chosen: MutationBase?) -> Self {
        Self(coverage: coverage, mutation: mutation, index: index, base: chosen)
    }
}
