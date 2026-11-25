//
//  DropOptions.swift
//  SwiftStatsCore
//
//  Which results a stored scan may let go (M5–M7): a scan replacing a
//  snapshot that holds coverage, mutation or T1 results it didn't collect
//  itself carries them, or is refused when it can't; `--drop-coverage`,
//  `--drop-mutation` and `--drop-index` replace the snapshot without them
//  instead.
//

/// The held results a save may drop rather than refuse over.
public struct DropOptions: OptionSet, Hashable, Sendable {
    /// Coverage (`--drop-coverage`).
    public static let coverage = Self(rawValue: 1 << 0)
    /// Mutation results (`--drop-mutation`).
    public static let mutation = Self(rawValue: 1 << 1)
    /// The T1 group's results: the build's, the index's and outskirts'
    /// (`--drop-index`). Accepted, but it drops nothing yet: no snapshot
    /// holds T1 results until the store keeps them (a placeholder; design
    /// §13, removed in step 8).
    public static let index = Self(rawValue: 1 << 2)

    /// The options as bits.
    public let rawValue: Int

    /// Options from their bits.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The options `--drop-coverage`, `--drop-mutation` and `--drop-index`
    /// give.
    public init(coverage: Bool, mutation: Bool, index: Bool) {
        self = [coverage ? .coverage : [], mutation ? .mutation : [], index ? .index : []]
    }
}
