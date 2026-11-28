//
//  ConfigBound.swift
//  SwiftStatsCoreTests
//
//  One edge of a bound PRD §10.1 states for a configuration value (P11.2):
//  the key it bounds, the value at the edge, which is accepted and read
//  as itself, the value one step outside it, which is refused with the
//  reason the reader gives, and the other keys the edge needs set or
//  removed (uneven clone mutation's `high` must lie above its `low`, each
//  as set, else its default). One step is a day for a duration, one for a
//  whole number, and the next `Double` for a number read as one
//  (`100.00000000000001` past 100, `5e-324` above 0), so an off-by-one or
//  a `<` for a `<=` shows on one side of the edge or the other. A value
//  far outside (below 0 for a floor, double a ceiling, `high` 10 under its
//  `low`) is refused alike, so a `!=` for a `>` shows too.
//

@testable import SwiftStatsCore
import Testing

/// One edge of a configuration value's bound.
struct ConfigBound: Sendable, CustomTestStringConvertible {
    /// What the edge is, as the walk names its case.
    let name: String
    /// The path of the bounded key.
    let path: [String]
    /// The value at the edge, as written plain.
    let edge: String
    /// The value one step outside the edge, as written plain.
    let outside: String
    /// A value far outside the edge, beyond `outside`, as written plain.
    let far: String
    /// The reason the reader refuses the value outside.
    let reason: String
    /// The bounded key's value in a configuration, nil when it isn't set.
    let read: @Sendable (SwiftStatsConfiguration) -> Double?
    /// Whether the value may be written quoted and read alike (not for
    /// swiftmutator's `workers` and `timeout`, which take only YAML
    /// numbers: design B33, awaiting U22).
    let isQuotable: Bool
    /// Other keys set before the edge (to the text given) or removed (nil).
    let others: [(path: [String], text: String?)]

    /// What the edge reads as: its number, a duration's `d` dropped.
    var value: Double? {
        Double(edge.hasSuffix("d") ? String(edge.dropLast()) : edge)
    }

    /// The edge's name, which names the walk's case.
    var testDescription: String {
        name
    }

    /// `members` with the other keys set or removed, then the bounded key
    /// written `text`, quoted as `quote` says.
    func applied(_ text: String, quote: YAMLDraft.Quote, to members: [YAMLDraft.Member]) -> [YAMLDraft.Member] {
        let prepared = others.reduce(members) { edited, other in
            guard let otherText = other.text else {
                return YAMLDraft.removing(at: other.path, in: edited)
            }
            return YAMLDraft.setting(.text(otherText), at: other.path, in: edited)
        }
        return YAMLDraft.setting(.scalar(text, quote), at: path, in: prepared)
    }
}
