//
//  GlobGen.swift
//  SwiftStatsCoreTests
//
//  Globs and paths for the glob properties (design §4.1.5). A glob's core
//  is a few atoms from a small alphabet, so matches and near misses
//  collide: two letters, the separator, regular-expression metacharacters
//  and other literals (an accent precomposed and decomposed among them),
//  the wildcards `*`, `?` and `**`, the forms whose stars other text
//  splits (`*?`, `**a`, `*/**`, `**/*/`: design B27's forms, which the
//  direct matcher made safe to draw), a wildcard or `/` joined by a
//  combining mark (ordinary text, as the glob is read in Characters), a
//  Prepend scalar (it joins the next Character, a `/` or a star, into
//  one), and, rarely, a line break. At most one leading `./` and up to two
//  trailing `/`s decorate it (design §3). The path is mostly the core
//  filled in atom by atom: every atom canonically but one by an edge fill
//  (a wildcard across a `/` or a line break, a `?` given a letter and a
//  combining mark, a marked wildcard given what the bare wildcard and the
//  mark would match, a metacharacter replaced), or each atom by its
//  canonical fill or a near miss (a star's fill holding `/`, a `?` given
//  two scalars, a letter swapped). Sometimes it is any pieces, and
//  sometimes a tail follows: a component under it, a line break, `\r\n`,
//  or a line break inside a component under it. Every line break PRD
//  §10.1 names is drawn: line feed and carriage return most, then vertical
//  tab, form feed, next line, line separator and paragraph separator. A
//  bounded case holds at most `GlobRegex.starLimit` stars, so the regular
//  expression reference reads it in bounded time. Lists are ordered
//  simplest first, so a failure shrinks toward its plainest form.
//

import Foundation
import PropertyBased

/// Generators of globs and the paths they are matched against.
enum GlobGen {
    /// The letters a core holds.
    static let letters = ["a", "b"]
    /// The separator.
    static let separator = "/"
    /// Regular-expression metacharacters, each a literal in a glob.
    static let metacharacters = [".", "$", "(", ")", "[", "]", "+", "^", "|", "\\", "{", "}"]
    /// The dot, a metacharacter drawn on its own as well, as paths hold it
    /// most (`x.swift`).
    static let dot = "."
    /// Other literals: a dash, a space, and an accent precomposed and
    /// decomposed.
    static let otherLiterals = ["-", " ", "\u{E9}", "e\u{301}"]
    /// The wildcards.
    static let wildcards = ["*", "?", "**"]
    /// Stars split by other text, design B27's forms.
    static let splitStars = ["*?", "**a", "*/**", "**/*/"]
    /// A star, a `?` and a `/` joined by a combining mark: ordinary text.
    static let markedWildcards = ["*\u{301}", "?\u{301}", "/\u{301}"]
    /// A Prepend scalar, which joins the Character after it into one.
    static let prepend = "\u{600}"
    /// The line breaks PRD §10.1 names besides line feed and carriage
    /// return: vertical tab, form feed, next line, line separator and
    /// paragraph separator. `**` and the folder extension stop at each, and
    /// one ending the path is ignored, as for the other two.
    static let rarerLineBreaks = ["\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]
    /// The line breaks a core rarely holds: all seven.
    static let lineBreaks = ["\n", "\r"] + rarerLineBreaks
    /// What stands for an atom past the star limit, and what starts or
    /// ends a core that would start with `./` or end in `/`.
    static let fallbackAtom = "a"
    /// How many atoms a core has (assumed: enough for a literal, a
    /// wildcard and a separator to meet, short enough to read when shrunk).
    static let atomCount = 0...8
    /// The most trailing `/`s a glob has.
    static let mostTrailingSlashes = 2
    /// The largest fill choice besides the canonical one; a choice is
    /// taken modulo the atom's fills.
    static let fillSpread = 5
    /// How many pieces a path of any pieces has.
    static let pieceCount = 0...8
    /// The pieces a path of any pieces is made of.
    static let pathPieces = ["a", "b", "/", ".", "x", "\u{E9}", "e\u{301}", "\n", "\r\n", "$", "*", "?"]
        + rarerLineBreaks
    /// Tails that put the path under what it fills: a component, two, and
    /// an empty one.
    static let underTails = ["/x", "/a/b", "/"]
    /// Tails that end the path in line breaks: a line feed, `\r\n`, a
    /// carriage return, and two line feeds (the rarer breaks come from
    /// `rarerLineBreaks`).
    static let breakTails = ["\n", "\r\n", "\r", "\n\n"]
    /// Tails that do both: a line break inside a component under the path,
    /// and a component ending in `\r\n`.
    static let mixedTails = ["/a\nb", "/x\r\n"]
    /// The fills of the wildcards, the separator and the letters, the
    /// canonical one first, then near misses. Keys are compared as Swift
    /// strings, canonically, so an accent's two forms can't both be keys:
    /// every other atom fills by `literalFills(of:)`.
    static let fillTable: [String: [String]] = [
        "*": ["", "a", "ab", "a/b", "\n", "\u{E9}"],
        "?": ["a", "", "/", "e\u{301}", "\n", "\u{1F1EF}\u{1F1F5}"],
        "*\u{301}": ["*\u{301}", "a\u{301}", "x", ""],
        "?\u{301}": ["?\u{301}", "e\u{301}", "x", ""],
        "**": ["", "a/b", "a", "a\nb", "/"],
        "*?": ["a", "ab", "", "a/b"],
        "**a": ["a", "x/a", "b", "x\na"],
        "*/**": ["a/", "a/b/c", "a", "/"],
        "**/*/": ["a/", "x/a/", "a", ""],
        "/": ["/", "", "//", "x"],
        "a": ["a", "b", "A"],
        "b": ["b", "a"]
    ]

    /// Weight of letters among the atoms.
    static let letterWeight = 4.0
    /// Weight of the separator and of the wildcards.
    static let commonWeight = 3.0
    /// Weight of literals other than letters.
    static let literalWeight = 2.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of a Prepend scalar and of a line break.
    static let rareWeight = 0.5
    /// Weight of an undecorated end, and of the canonical fill.
    static let plainWeight = 3.0
    /// The share of globs starting with `./`.
    static let rootPrefixRate: Float = 0.25
    /// The share of paths made of any pieces.
    static let piecesRate: Float = 0.2
    /// The share of paths with a tail.
    static let tailRate: Float = 0.5
    /// The share of filled paths in which one atom takes an edge fill,
    /// every other atom its canonical one: a wildcard filled across a `/`
    /// or a line break, a `?` filled with a letter and a combining mark, a
    /// wildcard joined by a mark filled with a letter and the mark, or a
    /// metacharacter replaced. These are the inputs on which a star or `?`
    /// crossing `/`, a star stopping at a line break, `**` crossing one, a
    /// `?` matching a Character, a glob read in scalars or a metacharacter
    /// read as a wildcard shows, and independent fill choices rarely make
    /// them (step 13c's calibration: 7 and 8 of 20 runs for a star or `?`
    /// crossing `/`, 1 and 5 for `.` read as a wildcard, 14 for a star
    /// stopping at a line break, 2 for a `?` matching a Character).
    static let edgeRate: Float = 0.5
    /// How many edge choices each atom has, at most: the edge choice
    /// picks the atom modulo the atoms that have edges, and then the fill.
    static let edgeSpread = 4
    /// The atoms that have edge fills, and theirs.
    static let edgeFills: [String: [String]] = metacharacters.reduce(into: [
        "*": ["a/b", "a\nb"],
        "?": ["/", "\n", "e\u{301}"],
        "**": ["a\nb", "a\rb"] + rarerLineBreaks.map { "a" + $0 + "b" },
        "*?": ["a/b", "\nb"],
        "*\u{301}": ["a\u{301}"],
        "?\u{301}": ["e\u{301}"]
    ]) { fills, metacharacter in
        fills[metacharacter] = ["x"]
    }

    /// One atom of a core.
    static let atom = Gen.frequency(
        (letterWeight, Pick.element(of: letters)),
        (commonWeight, Gen.always(separator)),
        (literalWeight, Pick.element(of: metacharacters + otherLiterals)),
        (classWeight, Gen.always(dot)),
        (commonWeight, Pick.element(of: wildcards)),
        (classWeight, Pick.element(of: splitStars)),
        (classWeight, Pick.element(of: markedWildcards)),
        (rareWeight, Gen.always(prepend)),
        (rareWeight, Pick.element(of: lineBreaks))
    )

    /// Whether a glob starts with `./`.
    static let rootPrefixed = Gen.bool(rootPrefixRate)

    /// How many `/`s end a glob.
    static let trailingSlashes = Gen.frequency(
        (plainWeight, Gen.always(0)),
        (classWeight, Gen<Int>.value(in: 1...mostTrailingSlashes))
    )

    /// The fill choice of each atom, by position, repeating when the list
    /// is shorter: none, so every atom takes its canonical fill, or a list
    /// mostly of canonical fills.
    static let fillChoices = Gen.frequency(
        (plainWeight, Gen.always([Int]())),
        (
            literalWeight,
            Gen.frequency((plainWeight, Gen.always(0)), (literalWeight, Gen<Int>.value(in: 1...fillSpread)))
                .array(of: atomCount)
        )
    )

    /// A tail: under the path, line breaks, or both, the rarer line breaks
    /// alone or inside a component under the path.
    static let tail = Gen.frequency(
        (commonWeight, Pick.element(of: underTails)),
        (literalWeight, Pick.element(of: breakTails)),
        (literalWeight, Pick.element(of: mixedTails)),
        (classWeight, Pick.element(of: rarerLineBreaks)),
        (classWeight, Pick.element(of: rarerLineBreaks).map { "/a" + $0 + "b" })
    )

    /// A glob and a path, the glob holding any number of stars.
    static let unbounded = glob(starLimit: Int.max)

    /// A glob and a path, the glob holding at most `GlobRegex.starLimit`
    /// stars, so the reference reads it in bounded time.
    static let bounded = glob(starLimit: GlobRegex.starLimit)

    /// A glob and a path, the glob holding at most `starLimit` `*` scalars.
    static func glob(starLimit: Int) -> Generator<GlobCase, AnySequence<Any>> {
        zip(
            atom.array(of: atomCount),
            rootPrefixed,
            trailingSlashes,
            fillChoices,
            Pick.element(of: pathPieces).array(of: pieceCount).optional(valueRate: piecesRate),
            tail.optional(valueRate: tailRate),
            Gen<Int>.value(in: 0...(atomCount.upperBound * edgeSpread)).optional(valueRate: edgeRate)
        )
        .map { atoms, hasRootPrefix, trailing, choices, pieces, ending, edgeChoice in
            let core = admissible(limited(atoms, starLimit: starLimit))
            let drawnEdge = pieces == nil ? edgeChoice.flatMap { edge(of: core, choosing: $0) } : nil
            let body = pieces?.joined() ?? filled(core, choices: choices, edge: drawnEdge)
            return GlobCase(
                atoms: core,
                hasRootPrefix: hasRootPrefix,
                trailingSlashes: trailing,
                path: body + (ending ?? ""),
                edgeAtom: drawnEdge?.atom,
                edgeFill: drawnEdge?.fill ?? ""
            )
        }
        .eraseToAny()
    }

    /// `atoms` with each atom that would take the core past `starLimit`
    /// `*` scalars replaced by `fallbackAtom`.
    static func limited(_ atoms: [String], starLimit: Int) -> [String] {
        var stars = 0
        var kept: [String] = []
        for drawn in atoms {
            let count = drawn.unicodeScalars.count { $0 == "*" }
            if stars + count <= starLimit {
                stars += count
                kept.append(drawn)
            } else {
                kept.append(fallbackAtom)
            }
        }
        return kept
    }

    /// `atoms` as a core that neither starts with `./` nor ends in `/`,
    /// isn't `.` (which a trailing `/` makes `./`, read as the root prefix:
    /// step 13c's first calibration found it), and that `./` before it and
    /// a `/` after it leave whole: a `fallbackAtom` before it or after it
    /// where needed.
    static func admissible(_ atoms: [String]) -> [String] {
        var core = atoms
        let start = core.joined()
        let rootPrefix = GlobCase.rootPrefix
        if start.hasPrefix(rootPrefix) || start == "." || (rootPrefix + start).hasPrefix(rootPrefix) == false {
            core.insert(fallbackAtom, at: 0)
        }
        let end = core.joined()
        if end.hasSuffix(separator) || (end + separator).hasSuffix(separator) == false {
            core.append(fallbackAtom)
        }
        return core
    }

    /// The fills of a literal atom: itself, its other canonical form when
    /// that has other scalars (an accent decomposed or precomposed), `x`,
    /// and nothing.
    static func literalFills(of atom: String) -> [String] {
        let twins = [atom.decomposedStringWithCanonicalMapping, atom.precomposedStringWithCanonicalMapping]
        let twin = twins.first { $0.unicodeScalars.elementsEqual(atom.unicodeScalars) == false }
        return [atom] + (twin.map { [$0] } ?? []) + ["x", ""]
    }

    /// The atom of `atoms` an edge choice gives an edge fill, and that
    /// fill: among the atoms with edge fills, the one at `choice` modulo
    /// their count, and its fill at `choice` divided by that count, modulo
    /// its fills; nil when no atom has edge fills.
    static func edge(of atoms: [String], choosing choice: Int) -> (atom: Int, fill: String)? {
        let edged = atoms.indices.filter { edgeFills[atoms[$0]] != nil }
        guard edged.isEmpty == false else {
            return nil
        }
        let place = edged[choice % edged.count]
        let fills = edgeFills[atoms[place]] ?? []
        return (place, fills[(choice / edged.count) % fills.count])
    }

    /// The path `atoms` fill in: with an `edge`, its atom by its fill and
    /// every other atom by its canonical one; else each atom by its fill at
    /// its choice, taken modulo its fills.
    static func filled(_ atoms: [String], choices: [Int], edge: (atom: Int, fill: String)?) -> String {
        atoms.indices
            .map { index in
                let fills = fillTable[atoms[index]] ?? literalFills(of: atoms[index])
                guard let edge else {
                    let choice = choices.isEmpty ? 0 : choices[index % choices.count]
                    return fills[choice % fills.count]
                }
                return index == edge.atom ? edge.fill : fills[0]
            }
            .joined()
    }
}
