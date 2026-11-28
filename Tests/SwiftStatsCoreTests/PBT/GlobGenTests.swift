import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the glob generator draws (design D14): from a fixed seed, a
/// thousand cases reach each antecedent of P10.2 an exact number of times
/// (a literal glob matching its own text, a path under it, or missing; one
/// holding a metacharacter; a glob starting `./` or ending in `/`; a star
/// glob without `**` matching a path or a path under it; a split star
/// form; a wildcard joined by a mark, and one filled as the bare wildcard
/// and the mark; a path ending in a line break, ending in a rarer one, or
/// holding a rarer one before its end; a wildcard filled across `/` or a
/// line break; a `?` filled with a letter and a mark; a metacharacter
/// filled otherwise), and
/// a thousand bounded cases reach each antecedent of the differential,
/// none past the reference's star limit. The counts hold under this
/// engine's generator code and this standard library; a change to either,
/// or to a weight or list in `GlobGen`, redraws them. Hand-worked examples
/// pin the generator's admissible cores and fills, and the reference,
/// `GlobRegex`.
@Suite("Glob generator")
struct GlobGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: nothing in the generator filters, so
    /// one is always enough.
    static let attempts = 1
    /// The fixed seed the meta-tests draw from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    @Test("a thousand cases reach each antecedent of P10.2 an exact number of times")
    func shapeClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let input = try GlobGen.unbounded.run(using: &random, limit: Self.attempts)
            let coreMatched = GlobPattern(input.core).matches(input.path)
            for label in GlobPatternPBT.shapeLabels(of: input, coreMatched: coreMatched) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "a ? filled with a letter and a combining mark": 18,
            "a glob ending in /": 239,
            "a glob holding a split star form": 228,
            "a glob holding a wildcard joined by a combining mark": 225,
            "a glob starting ./": 247,
            "a literal glob holding a regex metacharacter": 156,
            "a literal glob matching a path under it": 55,
            "a literal glob matching its own text": 147,
            "a literal glob missing its path": 211,
            "a metacharacter filled otherwise": 110,
            "a path ending in a line break": 267,
            "a path ending in a rarer line break": 105,
            "a path holding a rarer line break before its end": 254,
            "a star glob without ** matching a path under it": 19,
            "a star glob without ** matching its path": 77,
            "a wildcard filled across /": 37,
            "a wildcard filled across a line break": 94,
            "a wildcard joined by a mark filled as the bare wildcard and the mark": 23
        ])
    }

    @Test("a thousand bounded cases reach each antecedent of the differential, none past the star limit")
    func agreementClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        var unbounded = 0
        for _ in 0..<Self.draws {
            let input = try GlobGen.bounded.run(using: &random, limit: Self.attempts)
            let matched = GlobPattern(input.glob).matches(input.path)
            for label in GlobPatternPBT.agreementLabels(of: input, matched: matched) {
                counts[label, default: 0] += 1
            }
            if GlobRegex.isBounded(input.glob) == false {
                unbounded += 1
            }
        }

        #expect(unbounded == 0)
        #expect(counts == [
            "a ? filled with a letter and a combining mark": 18,
            "a glob holding a split star form": 206,
            "a glob holding a wildcard joined by a combining mark": 223,
            "a glob starting ./": 247,
            "a metacharacter filled otherwise": 112,
            "a path ending in a line break": 267,
            "a path ending in a rarer line break": 105,
            "a path holding a rarer line break before its end": 252,
            "a wildcard filled across /": 38,
            "a wildcard filled across a line break": 87,
            "a wildcard joined by a mark filled as the bare wildcard and the mark": 24,
            "both matching": 426,
            "both missing": 574
        ])
    }

    @Test("""
        a core that would be ., start with ./ or end in / or a Prepend scalar gains an a, and stars past the limit \
        become a's
        """)
    func admissibleCores() {
        #expect(GlobGen.admissible([".", "/", "b"]) == ["a", ".", "/", "b"])
        #expect(GlobGen.admissible(["."]) == ["a", "."])
        #expect(GlobGen.admissible(["b", "/"]) == ["b", "/", "a"])
        #expect(GlobGen.admissible(["b", "\u{600}"]) == ["b", "\u{600}", "a"])
        #expect(GlobGen.admissible(["b", "/\u{301}"]) == ["b", "/\u{301}"])
        #expect(GlobGen.admissible([]).isEmpty)
        #expect(GlobGen.limited(["**/*/", "*?", "*", "?"], starLimit: 4) == ["**/*/", "*?", "a", "?"])
    }

    @Test("""
        a core fills atom by atom, each choice taken modulo the atom's fills, an unlisted atom as itself, and an \
        edge fills one atom by its edge fill and the rest canonically
        """)
    func fills() {
        #expect(GlobGen.filled(["a", "*", ".", "?"], choices: [], edge: nil) == "a.a")
        #expect(GlobGen.filled(["a", "*", ".", "?"], choices: [0, 3, 1, 2], edge: nil) == "aa/bx/")
        #expect(GlobGen.filled(["*", "*"], choices: [9], edge: nil) == "a/ba/b")
        #expect(GlobGen.filled(["a", "*", ".", "?"], choices: [0, 3, 1, 2], edge: (3, "/")) == "a./")
        let atoms = ["a", "*", ".", "?", "b"]
        let edges = [0, 1, 2, 3, 4, 5].compactMap { GlobGen.edge(of: atoms, choosing: $0) }
        #expect(edges.map(\.atom) == [1, 2, 3, 1, 2, 3])
        #expect(edges.map(\.fill) == ["a/b", "x", "/", "a\nb", "x", "\n"])
        #expect(GlobGen.edge(of: ["a", "b", "-"], choosing: 0) == nil)
    }

    @Test("the reference reads stars two at a time, escapes every other Character, and extends to the folders under it")
    func referenceExpressions() {
        #expect(GlobRegex.expression(for: "./a.b/") == "^a\\.b(/.*)?$")
        #expect(GlobRegex.expression(for: "***/?") == "^.*[^/]*\\/[^/](/.*)?$")
        #expect(GlobRegex.expression(for: "**/x") == "^(.*/)?x(/.*)?$")
        #expect(GlobRegex.expression(for: "*\u{301}") == "^\\*\u{301}(/.*)?$")
        #expect(GlobRegex.answer("Sources/Generated", "Sources/Generated/A.swift") == .matches)
        #expect(GlobRegex.answer("a", "a\r\n") == .matches)
        #expect(GlobRegex.answer("a?", "a\r\n") == .misses)
        #expect(GlobRegex.answer("?", "e\u{301}") == .misses)
        #expect(GlobRegex.isBounded("**/*?") && GlobRegex.isBounded("*?*?*?*?*") == false)
    }
}
