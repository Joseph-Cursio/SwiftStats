//
//  GlobPatternPBT+Agreement.swift
//  SwiftStatsCoreTests
//
//  The glob differential: `GlobPattern`'s direct matcher (design B27)
//  answers as `GlobRegex`, PRD §10.1 written as the ICU regular
//  expression the matcher replaced, on every glob of at most
//  `GlobRegex.starLimit` stars, where the reference runs in bounded time.
//  Step 13b compared the two over 71.4 million fixed pairs before the
//  replacement; this keeps them compared on fresh draws, the line-break,
//  Character and split-star edges among them.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// The glob differential.
extension GlobPatternPBT {
    /// A planted defect, an input on which it answers otherwise than the
    /// reference, and its answer there.
    struct AgreementDefect {
        /// What the defect is.
        let defect: String
        /// The input that shows it.
        let input: GlobCase
        /// What the defect answers for the input.
        let answer: Bool

        /// The defect `defect`, answering `answer` for `glob` against `path`.
        init(_ defect: String, _ glob: String, against path: String, answer: Bool) {
            self.defect = defect
            input = GlobPatternPBT.written(glob, against: path)
            self.answer = answer
        }
    }

    /// The differential's base runs, over the engine's 100: one input
    /// costs tens of microseconds, most of it compiling the reference's
    /// expression. The rarest antecedent, a `?` filled with a letter and a
    /// combining mark, the input on which a `?` matching a Character shows,
    /// comes in 18 of the meta-test's 1,000 bounded cases (design D14:
    /// `(1 - 0.018)^800`, about 5 * 10^-7, is the most a run misses it;
    /// 300 runs would miss it about 4 * 10^-3 of the time).
    static let agreementRuns = 800
    /// What the differential's tally counts when both match.
    static let bothMatch = "both matching"
    /// What it counts when both miss.
    static let bothMiss = "both missing"
    /// The antecedents the differential must reach at least once each.
    static let agreementAntecedents = [
        bothMatch, bothMiss, splitStar, markedWildcard, breakEnded, rarerBreakEnded, rarerBreakInside, rootPrefixed,
        slashCrossed, breakCrossed, metacharacterMissed, markFilled, markedFilled
    ]

    /// The classes `input` falls in, for the differential's tally and the
    /// generator's meta-test, `matched` saying whether the glob matches.
    static func agreementLabels(of input: GlobCase, matched: Bool) -> [String] {
        let classes = [
            splitStar, markedWildcard, breakEnded, rarerBreakEnded, rarerBreakInside, rootPrefixed, slashCrossed,
            breakCrossed, metacharacterMissed, markFilled, markedFilled
        ]
        let shared = shapeLabels(of: input, coreMatched: matched).filter(classes.contains)
        return [matched ? bothMatch : bothMiss] + shared
    }

    /// A glob as written, undecorated, against `path`.
    static func written(_ glob: String, against path: String) -> GlobCase {
        GlobCase(atoms: [glob], hasRootPrefix: false, trailingSlashes: 0, path: path, edgeAtom: nil, edgeFill: "")
    }

    /// Whether `direct`, what `GlobPattern` answered for `input`, is
    /// `reference`, what `GlobRegex` answered, on a glob the reference
    /// reads in bounded time. Records an issue for each law that fails.
    static func checkAgreement(_ input: GlobCase, direct: Bool, reference: GlobRegex.Answer) -> Bool {
        let expression = GlobRegex.expression(for: input.glob)
        let answer: GlobRegex.Answer = direct ? .matches : .misses
        return holds(
            [
                (
                    GlobRegex.isBounded(input.glob),
                    "holds more than \(GlobRegex.starLimit) stars, past the reference's bound"
                ),
                (reference != .unreadable, "has a reference expression that doesn't compile: " + expression),
                (
                    reference == .unreadable || answer == reference,
                    "\(answer), but the regular expression \(expression) \(reference)"
                )
            ],
            subject: "the glob"
        )
    }

    // MARK: The differential

    /// Invariant: on every glob of at most four stars and every path, the
    /// direct matcher answers as the regular expression it replaced.
    /// Why it holds: `GlobPattern`'s header (design B27: it answers exactly
    /// as the regular expression did), step 13b's differential over 71.4
    /// million pairs, and PRD §10.1, which both are read from.
    /// Why it might not: the reference backtracks exponentially in the
    /// stars of a failed match (B4, B27), so globs of more than
    /// `GlobRegex.starLimit` stars are left out (assumed bound, the
    /// reference's, not the matcher's); the reference leaves out B4's
    /// joining of star runs, which matched what the stars did one by one.
    /// Oracle: reference (`GlobRegex`); planted defects: `**/` never empty,
    /// a star stopping at a line break, `**` crossing a line break, a `?`
    /// matching a Character, a star crossing `/`, no folder extension, no
    /// final break ignored, a next line or paragraph separator not read as
    /// a line break, and the glob read in scalars, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "on every glob of at most four stars, the direct matcher answers as the regular expression it replaced",
        .timeLimit(PBTBudget.timeLimit)
    )
    func directMatcherAgreesWithTheRegex() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.agreementRuns), input: GlobGen.bounded) { input in
            PBTTrace.note(input)
            let direct = GlobPattern(input.glob).matches(input.path)
            Self.agreementLabels(of: input, matched: direct).forEach(tally.fire)
            let reference = GlobRegex.answer(input.glob, input.path)
            if Self.checkAgreement(input, direct: direct, reference: reference) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.agreementAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("the globs of the fixed examples answer as the regular expression does")
    func fixedGlobsAgree() {
        let pairs = [
            ("Sources/*.swift", "Sources/A.swift"), ("Sources/*.swift", "Sources/Lib/A.swift"),
            ("**/Generated/*.swift", "Sources/Lib/Generated/A.swift"), ("**/Generated/*.swift", "Generated/A.swift"),
            ("Sources/**", "Sources/Lib/Deep/A.swift"), ("./Sources/Generated/", "Sources/Generated/A.swift"),
            ("Sources/Gen", "Sources/Generated/A.swift"), ("Gen*", "Generated/x.swift"),
            ("Gen*", "Sources/Generated/x.swift"), ("***/a", "a"), ("x/***", "x/a\nb"), ("a/**", "a")
        ]

        for (glob, path) in pairs {
            let input = Self.written(glob, against: path)
            let direct = GlobPattern(glob).matches(path)

            #expect(Self.checkAgreement(input, direct: direct, reference: GlobRegex.answer(glob, path)))
        }
    }

    @Test("a line break, any of the seven, or a decomposed accent answers as the regular expression does")
    func lineBreakEdgesAgree() {
        let pairs = [
            ("a", "a\r\n"), ("a", "a\n\n"), ("a?", "a\r\n"), ("a?", "a\r"), ("a", "a\u{2028}"), ("a**", "a/b\nc"),
            ("a*", "a\nb"), ("?", "e\u{301}"), ("??", "e\u{301}"), ("\u{E9}", "e\u{301}"), ("*\u{301}", "a\u{301}"),
            ("?\u{301}", "e\u{301}"), ("a", "a\u{0B}"), ("a", "a\u{0C}"), ("a", "a\u{85}"), ("a", "a\u{2029}"),
            ("a**", "a/b\u{0B}c"), ("a**", "a/b\u{0C}c"), ("a**", "a/b\u{85}c"), ("a**", "a/b\u{2029}c"),
            ("a**", "a/b\u{2028}c"), ("a", "a/b\u{85}c")
        ]

        for (glob, path) in pairs {
            let input = Self.written(glob, against: path)
            let direct = GlobPattern(glob).matches(path)

            #expect(Self.checkAgreement(input, direct: direct, reference: GlobRegex.answer(glob, path)))
        }
    }

    @Test("B27's split star forms, at four stars, answer as the regular expression does")
    func splitStarsAgree() {
        let pairs = [
            ("*?*?x", "aaaa"), ("*?*?", "ab"), ("**a**a", "xa/ya"), ("**a**ax", "aaaa"), ("*/***/a", "b/c/a"),
            ("**/*/a", "b/c/a"), ("**/*/a", "a"), ("*/**", "b/c")
        ]

        for (glob, path) in pairs {
            let input = Self.written(glob, against: path)
            let direct = GlobPattern(glob).matches(path)

            #expect(Self.checkAgreement(input, direct: direct, reference: GlobRegex.answer(glob, path)))
        }
    }

    /// Each planted defect, with an input where it answers otherwise than
    /// the regular expression, and its answer there: `**/` never empty
    /// misses `a` under `**/a`; a star stopping at a line break misses
    /// `a\nb` under `a*`; `**` crossing one matches `a/b\nc` under `a**`;
    /// a `?` matching a Character matches `e` and a mark; a star crossing
    /// `/` matches `ab/c` under `a*c`; no folder extension misses `ab/c`
    /// under `a*`; no final break ignored misses `a\n` under `a`; a next
    /// line not read as a line break misses `a` and one; a paragraph
    /// separator not read as one lets `**` match across it; and a glob read
    /// in scalars matches `a` and a mark under a star and that mark. Each
    /// input is checked to show its defect: the reference answers the
    /// other way.
    @Test("a planted defect's answer, where the regular expression answers otherwise, fails the differential")
    func agreementDefectsDetected() {
        let defects = [
            AgreementDefect("**/ never empty", "**/a", against: "a", answer: false),
            AgreementDefect("a star stopping at a line break", "a*", against: "a\nb", answer: false),
            AgreementDefect("** crossing a line break", "a**", against: "a/b\nc", answer: true),
            AgreementDefect("a ? matching a Character", "?", against: "e\u{301}", answer: true),
            AgreementDefect("a star crossing /", "a*c", against: "ab/c", answer: true),
            AgreementDefect("no folder extension", "a*", against: "ab/c", answer: false),
            AgreementDefect("no final line break ignored", "a", against: "a\n", answer: false),
            AgreementDefect("a next line not a line break", "a", against: "a\u{85}", answer: false),
            AgreementDefect("a paragraph separator not a line break", "a**", against: "a/b\u{2029}c", answer: true),
            AgreementDefect("the glob read in scalars", "*\u{301}", against: "a\u{301}", answer: true)
        ]

        for planted in defects {
            let reference = GlobRegex.answer(planted.input.glob, planted.input.path)

            #expect(
                reference == (planted.answer ? .misses : .matches),
                "the input doesn't show the defect: \(planted.defect)"
            )
            PlantedDefect.expectDetected(planted.defect, sourceLocation: #_sourceLocation) {
                Self.checkAgreement(planted.input, direct: planted.answer, reference: reference)
            }
        }
    }
}
