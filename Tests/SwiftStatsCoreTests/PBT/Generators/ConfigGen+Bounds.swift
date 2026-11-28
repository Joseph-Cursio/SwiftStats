//
//  ConfigGen+Bounds.swift
//  SwiftStatsCoreTests
//
//  P11.2's inputs for one edge (design §4.1.6: "walk over the bounds,
//  sampled over styles"): the edge, the value one step outside it, or the
//  value far outside it, a third of the time each; written plain, single-
//  or double-quoted where the key takes a quoted value (not swiftmutator's
//  `workers` and `timeout`, design B33, awaiting U22); in a valid
//  configuration laid out in block style, flow style from any depth, after
//  any prefix, with either line end.
//

import PropertyBased

/// Generators of a bound's edge in a configuration.
extension ConfigGen {
    /// The sides of an edge a case is drawn on: the edge, one step
    /// outside, far outside.
    static let boundSides = 3

    /// The edge of `bound`, or a value outside it, in a valid
    /// configuration.
    static func boundCase(_ bound: ConfigBound) -> Generator<BoundCase, AnySequence<Any>> {
        zip(Gen<Int>.value(in: 0...(boundSides - 1)), Pick.element(of: quotes), valid, layout)
            .map { side, quote, members, layout in
                BoundCase(
                    bound: bound,
                    isOutside: side > 0,
                    isFar: side > 1,
                    quote: bound.isQuotable ? quote : .plain,
                    members: members,
                    layout: layout
                )
            }
            .eraseToAny()
    }
}
