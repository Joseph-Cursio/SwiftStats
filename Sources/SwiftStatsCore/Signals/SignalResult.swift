//
//  SignalResult.swift
//  SwiftStatsCore
//
//  One signal in a report: its members ranked by score, or why it was left
//  out (PRD §6.5: a signal whose inputs are missing is never computed from
//  partial data).
//

/// A computed signal, or the reason it wasn't.
public struct SignalResult: Codable, Hashable, Sendable {
    /// The signal.
    public let name: SignalName
    /// Why it was left out; nil when computed.
    public let leftOut: String?
    /// How membership was decided, such as "top 10% of 812 candidates".
    public let rule: String
    /// The size of the pool it was computed over.
    public let candidates: Int
    /// What it lists, in its order: a ranked signal's candidates scoring
    /// above zero, members first; another signal's members.
    public let items: [SignalItem]

    /// The members.
    public var members: [SignalItem] {
        items.filter(\.member)
    }
}
