//
//  BoundCase.swift
//  SwiftStatsCoreTests
//
//  One input of P11.2: a bound's edge, the value one step outside it, or
//  a value far outside it, written plain or quoted into a valid
//  configuration (its other keys set or removed as the edge needs), laid
//  out in block or flow style.
//

import Testing

/// A bound's edge, or a value outside it, in a configuration.
struct BoundCase: Sendable, CustomTestStringConvertible {
    /// The edge.
    let bound: ConfigBound
    /// Whether the value is outside the edge.
    let isOutside: Bool
    /// Whether a value outside is the far one, not the one a step out.
    let isFar: Bool
    /// How the value is written.
    let quote: YAMLDraft.Quote
    /// The valid configuration's members, around the value.
    let members: [YAMLDraft.Member]
    /// How the text is laid out.
    let layout: ConfigLayout

    /// The value written.
    var written: String {
        guard isOutside else {
            return bound.edge
        }
        return isFar ? bound.far : bound.outside
    }

    /// The configuration's text.
    var text: String {
        layout.text(of: bound.applied(written, quote: quote, to: members))
    }

    /// The edge, the side and the text, in ASCII, so a failure's seed
    /// reaches the console.
    var testDescription: String {
        let side = isOutside ? (isFar ? "far outside" : "outside") : "at"
        return PBTTrace.ascii("\(side) \(bound.name), \(written) \(quote): YAML \(text.debugDescription)")
    }
}
