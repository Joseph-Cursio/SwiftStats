//
//  JSONFlag.swift
//  SwiftStatsCore
//
//  A JSON boolean that may be left out (M6, design §2, §3): SwiftMutator
//  leaves some out, and the scan JSON's mutation block writes a tri-state
//  (a mutant's `activated`, `killedByComplete` and `suspectOnly`, a run's
//  `suspectsJudged`) as `true`, `false` or absent. A property of this
//  type, optional, reads and writes one without an optional `Bool`.
//

/// A JSON boolean.
public struct JSONFlag: Codable, Hashable, Sendable {
    /// Its value.
    public let value: Bool

    /// The flag `value`.
    public init(_ value: Bool) {
        self.value = value
    }

    /// Reads a JSON boolean.
    public init(from decoder: any Decoder) throws {
        value = try decoder.singleValueContainer().decode(Bool.self)
    }

    /// Writes it as a JSON boolean.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
