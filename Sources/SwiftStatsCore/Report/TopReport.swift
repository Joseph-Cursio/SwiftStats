//
//  TopReport.swift
//  SwiftStatsCore
//
//  `swiftstats top <signal> --format json` (PRD §10): one signal's ranking
//  for a snapshot, members marked, cut to the requested length, with how
//  many items it ranks and how many are members before the cut.
//

/// One signal's ranking, as `top` writes it.
public struct TopReport: Codable, Hashable, Sendable {
    /// The version of this document's format: 2 names each item's
    /// `subject` (it was `family`) and moves its inputs into payloads, M3's
    /// into `history` (M4); 3 adds the coverage signals and their payloads,
    /// `markers`, `coverage` and a clone class's `coverage` (M5); 4 adds the
    /// mutation signals and their payloads, `mutation`, `ratio`,
    /// `propertyTarget` and a clone class's `mutation` (M6).
    public static let currentSchemaVersion = 4

    /// The document's format version.
    public let schemaVersion: Int
    /// The package.
    public let package: String
    /// The snapshot's commit; nil outside git.
    public let commit: String?
    /// The signal, with at most the requested number of items.
    public let signal: SignalResult
    /// How many items the signal ranks, before the cut.
    public let ranked: Int
    /// How many of those are members, before the cut.
    public let members: Int

    /// The ranking of `signal` in `snapshot`, keeping its first `limit` items.
    public init(snapshot: SnapshotInfo, signal: SignalResult, limit: Int) {
        schemaVersion = Self.currentSchemaVersion
        package = snapshot.package
        commit = snapshot.git.commit
        ranked = signal.items.count
        members = signal.members.count
        self.signal = SignalResult(
            name: signal.name,
            leftOut: signal.leftOut,
            rule: signal.rule,
            candidates: signal.candidates,
            items: Array(signal.items.prefix(limit))
        )
    }
}
