//
//  ConfigGen+Bounds.swift
//  SwiftStatsCoreTests
//
//  P11.2's inputs for one edge (design §4.1.6: "walk over the bounds,
//  sampled over styles"): the edge or the value one step outside it, each
//  half the time; written plain, single- or double-quoted where the key
//  takes a quoted value (not swiftmutator's `workers` and `timeout`,
//  design B33, awaiting U22); in a valid configuration laid out in block
//  style, flow style from any depth, after any prefix, with either line
//  end.
//

import PropertyBased

/// Generators of a bound's edge in a configuration.
extension ConfigGen {
    /// The edge of `bound`, or the value just outside it, in a valid
    /// configuration.
    static func boundCase(_ bound: ConfigBound) -> Generator<BoundCase, AnySequence<Any>> {
        zip(Gen.bool(), Pick.element(of: quotes), valid, layout)
            .map { isOutside, quote, members, layout in
                BoundCase(
                    bound: bound,
                    isOutside: isOutside,
                    quote: bound.isQuotable ? quote : .plain,
                    members: members,
                    layout: layout
                )
            }
            .eraseToAny()
    }
}
