//
//  GlobPatternPBT+Shapes.swift
//  SwiftStatsCoreTests
//
//  P10.2's examples, each calling its check on globs a configuration
//  writes, and its planted defects: what a matcher that let a star or a
//  `?` cross `/`, kept the leading `./` or a trailing `/`, dropped the
//  folder extension, read `.` as a wildcard, mishandled a line break
//  ending the path, left one of PRD §10.1's line breaks out, or read the
//  glob in scalars would answer, each fed to the check, which must detect
//  it.
//

@testable import SwiftStatsCore
import Testing

/// P10.2's examples and planted defects.
extension GlobPatternPBT {
    /// `input` with what `GlobPattern` answers for it, or a planted defect
    /// would, as P10.2's check takes them.
    struct ShapeAnswers {
        /// The input.
        let input: GlobCase
        /// Whether the glob as written matches the path.
        let matched: Bool
        /// Whether the core matches the path.
        let coreMatched: Bool
        /// Whether the glob as written and its core are equal globs.
        let sameGlob: Bool
        /// Each core component against the path's in its place, or none.
        let partMatches: [Bool]
    }

    /// A glob of `atoms`, starting `./` when `rooted`, ending in
    /// `trailing` `/`s, against `path`.
    static func globCase(_ atoms: [String], rooted: Bool, trailing: Int, path: String) -> GlobCase {
        GlobCase(
            atoms: atoms,
            hasRootPrefix: rooted,
            trailingSlashes: trailing,
            path: path,
            edgeAtom: nil,
            edgeFill: ""
        )
    }

    /// A planted defect's answers for a glob of `atoms`, undecorated,
    /// against `path`: `answer` for the glob and its core alike, no
    /// component reading.
    static func plainAnswer(_ atoms: [String], against path: String, answer: Bool) -> ShapeAnswers {
        ShapeAnswers(
            input: globCase(atoms, rooted: false, trailing: 0, path: path),
            matched: answer,
            coreMatched: answer,
            sameGlob: true,
            partMatches: []
        )
    }

    @Test("a folder written ./Sources/Generated/ is Sources/Generated, and matches the files under it")
    func folderGlobShape() {
        let paths = [
            ("Sources/Generated", true), ("Sources/Generated/A.swift", true), ("Sources/Generated/Deep/B.swift", true),
            ("Sources/GeneratedA.swift", false), ("Sources/Lib/A.swift", false), ("Sources/Generated\n", true)
        ]

        for (path, expected) in paths {
            let input = Self.globCase(["Sources", "/", "Generated"], rooted: true, trailing: 1, path: path)
            let matched = GlobPattern(input.glob).matches(input.path)
            let passed = Self.checkShape(
                input,
                matched: matched,
                coreMatched: GlobPattern(input.core).matches(input.path),
                sameGlob: GlobPattern(input.glob) == GlobPattern(input.core),
                partMatches: Self.componentPairs(of: input).map { GlobPattern($0.glob).matches($0.path) }
            )

            #expect(passed)
            #expect(matched == expected)
        }
    }

    @Test("a glob of regular-expression metacharacters matches only its own text and the paths under it")
    func metacharacterGlobShape() {
        let atoms = ["a", "[", "b", "]", "+", ".", "$", "(", "|", ")", "^", "{", "}", "\\"]
        let paths = [
            ("a[b]+.$(|)^{}\\", true), ("a[b]+.$(|)^{}\\/x.swift", true), ("ab", false), ("a[b]+x$(|)^{}\\", false)
        ]

        for (path, expected) in paths {
            let input = Self.globCase(atoms, rooted: false, trailing: 0, path: path)
            let matched = GlobPattern(input.glob).matches(input.path)
            let passed = Self.checkShape(
                input,
                matched: matched,
                coreMatched: GlobPattern(input.core).matches(input.path),
                sameGlob: GlobPattern(input.glob) == GlobPattern(input.core),
                partMatches: Self.componentPairs(of: input).map { GlobPattern($0.glob).matches($0.path) }
            )

            #expect(passed)
            #expect(matched == expected)
        }
    }

    @Test("Sources/*.swift matches a file of Sources, and a path under one, but no file deeper down")
    func starGlobShape() {
        let paths = [
            ("Sources/A.swift", true), ("Sources/A.swift/x", true), ("Sources/Lib/A.swift", false),
            ("Sources/.swift", true)
        ]

        for (path, expected) in paths {
            let input = Self.globCase(["Sources", "/", "*", ".", "swift"], rooted: false, trailing: 0, path: path)
            let matched = GlobPattern(input.glob).matches(input.path)
            let passed = Self.checkShape(
                input,
                matched: matched,
                coreMatched: GlobPattern(input.core).matches(input.path),
                sameGlob: GlobPattern(input.glob) == GlobPattern(input.core),
                partMatches: Self.componentPairs(of: input).map { GlobPattern($0.glob).matches($0.path) }
            )

            #expect(passed)
            #expect(matched == expected)
        }
    }

    /// Each planted defect's answers: a star crossing `/` lets `a*c` match
    /// `ab/xc`, and a `?` matching `/` lets `a?b` match `a/b`, though the
    /// first component misses; keeping the leading `./` or the trailing
    /// `/` makes `./a` or `a/` miss `a` and differ from `a`.
    @Test("a planted defect's answer for a star or ? crossing /, or a ./ or / kept, fails P10.2's law")
    func shapeDefectsDetected() {
        let crossing = Self.globCase(["a", "*", "c"], rooted: false, trailing: 0, path: "ab/xc")
        let question = Self.globCase(["a", "?", "b"], rooted: false, trailing: 0, path: "a/b")
        let rooted = Self.globCase(["a"], rooted: true, trailing: 0, path: "a")
        let slashed = Self.globCase(["a"], rooted: false, trailing: 1, path: "a")
        let defects: [(defect: String, answers: ShapeAnswers)] = [
            (
                "a star crossing /",
                ShapeAnswers(input: crossing, matched: true, coreMatched: true, sameGlob: true, partMatches: [false])
            ),
            (
                "a ? matching /",
                ShapeAnswers(input: question, matched: true, coreMatched: true, sameGlob: true, partMatches: [false])
            ),
            (
                "the leading ./ kept",
                ShapeAnswers(input: rooted, matched: false, coreMatched: true, sameGlob: false, partMatches: [true])
            ),
            (
                "the trailing / kept",
                ShapeAnswers(input: slashed, matched: false, coreMatched: true, sameGlob: false, partMatches: [true])
            )
        ]

        for (defect, answers) in defects {
            PlantedDefect.expectDetected(defect, sourceLocation: #_sourceLocation) {
                Self.checkShape(
                    answers.input,
                    matched: answers.matched,
                    coreMatched: answers.coreMatched,
                    sameGlob: answers.sameGlob,
                    partMatches: answers.partMatches
                )
            }
        }
    }

    /// Each planted defect's answer for a glob with no wildcard: no folder
    /// extension misses `a.b/c` under `a.b`; `.` read as a wildcard matches
    /// `axb`; `\r\n` not ignored as one break misses `a\r\n` under `a`; no
    /// final break ignored misses `a\n`; the folder extension crossing a
    /// line break matches `a/b\nc`; a next line not read as a line break
    /// misses `a` and one; a paragraph separator not read as one lets the
    /// folder extension cross it; and a glob read in scalars matches `a`
    /// and a mark under a star and that mark.
    @Test("a planted defect's answer for a literal glob, its folders or a line break ending the path fails P10.2's law")
    func literalDefectsDetected() {
        let defects: [(defect: String, answers: ShapeAnswers)] = [
            ("no folder extension", Self.plainAnswer(["a", ".", "b"], against: "a.b/c", answer: false)),
            ("a dot read as a wildcard", Self.plainAnswer(["a", ".", "b"], against: "axb", answer: true)),
            ("\\r\\n not ignored as one line break", Self.plainAnswer(["a"], against: "a\r\n", answer: false)),
            ("no final line break ignored", Self.plainAnswer(["a"], against: "a\n", answer: false)),
            ("the folder extension crossing a line break", Self.plainAnswer(["a"], against: "a/b\nc", answer: true)),
            ("a next line not a line break", Self.plainAnswer(["a"], against: "a\u{85}", answer: false)),
            (
                "a paragraph separator not a line break",
                Self.plainAnswer(["a"], against: "a/b\u{2029}c", answer: true)
            ),
            ("the glob read in scalars", Self.plainAnswer(["*\u{301}"], against: "a\u{301}", answer: true))
        ]

        for (defect, answers) in defects {
            PlantedDefect.expectDetected(defect, sourceLocation: #_sourceLocation) {
                Self.checkShape(
                    answers.input,
                    matched: answers.matched,
                    coreMatched: answers.coreMatched,
                    sameGlob: answers.sameGlob,
                    partMatches: answers.partMatches
                )
            }
        }
    }
}
