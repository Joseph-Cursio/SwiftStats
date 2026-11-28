//
//  BoundCase.swift
//  SwiftStatsCoreTests
//
//  One input of P11.2: a bound's edge or the value one step outside it,
//  written plain or quoted into a valid configuration (its other keys
//  set or removed as the edge needs), laid out in block or flow style.
//

import Testing

/// A bound's edge, or the value just outside it, in a configuration.
struct BoundCase: Sendable, CustomTestStringConvertible {
    /// The edge.
    let bound: ConfigBound
    /// Whether the value is the one outside the edge.
    let isOutside: Bool
    /// How the value is written.
    let quote: YAMLDraft.Quote
    /// The valid configuration's members, around the value.
    let members: [YAMLDraft.Member]
    /// How the text is laid out.
    let layout: ConfigLayout

    /// The value written.
    var written: String {
        isOutside ? bound.outside : bound.edge
    }

    /// The configuration's text.
    var text: String {
        layout.text(of: bound.applied(written, quote: quote, to: members))
    }

    /// The edge, the side and the text, in ASCII, so a failure's seed
    /// reaches the console.
    var testDescription: String {
        let side = isOutside ? "outside" : "at"
        return PBTTrace.ascii("\(side) \(bound.name), \(written) \(quote): YAML \(text.debugDescription)")
    }
}
