//
//  DropOptions.swift
//  SwiftStatsCore
//
//  Which results a stored scan may let go (M5, M6, design §6.4): a scan
//  replacing a snapshot that holds coverage or mutation results it didn't
//  collect itself carries them, or is refused when it can't; `--drop-coverage`
//  and `--drop-mutation` replace the snapshot without them instead.
//

/// The held results a save may drop rather than refuse over.
public struct DropOptions: OptionSet, Hashable, Sendable {
    /// Coverage (`--drop-coverage`).
    public static let coverage = Self(rawValue: 1 << 0)
    /// Mutation results (`--drop-mutation`).
    public static let mutation = Self(rawValue: 1 << 1)

    /// The options as bits.
    public let rawValue: Int

    /// Options from their bits.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The options `--drop-coverage` and `--drop-mutation` give.
    public init(coverage: Bool, mutation: Bool) {
        self = [coverage ? .coverage : [], mutation ? .mutation : []]
    }
}
