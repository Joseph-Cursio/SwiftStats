import Foundation
@testable import SwiftStatsCore
import Testing

/// Genuinely under-tested (PRD §8, M6, design §7.2): production functions
/// with at least 3 scored mutants, at most 20% of lines covered and a
/// function score below 20%, in a module with no test code, a test-to-code
/// line ratio below the project's, or below
/// `signals.genuinely-under-tested.ratio` when set; scored by unkilled
/// mutants, ordered by score, then line coverage cross-multiplied. Left out
/// when the results don't list code no test ran; with one production module
/// whose tests are measured, nothing can be listed without the ratio.
@Suite("Genuinely under-tested")
struct GenuinelyUnderTestedTests {
    /// The harness's shorthand.
    private typealias Harness = MutationSignalHarness

    /// A function with `covered` of `total` lines run and `mutants`.
    private static func function(_ covered: Int, of total: Int, _ mutants: [Harness.Planted]) -> Harness.Function {
        Harness.Function(lines: Harness.lines(covered, of: total), mutants: mutants)
    }

    /// An uncovered function with `count` not-covered mutants.
    private static func uncovered(_ count: Int) -> Harness.Function {
        function(0, of: Harness.functionLines, Harness.planted(count, .notCovered))
    }

    @Test("""
        a barely covered, barely killed function is listed in the module whose ratio lies below the project's and \
        counted in the other; items score by unkilled mutants, and a tie puts the lower line coverage first, though \
        its subject sorts later
        """)
    func modules() throws {
        let snapshot = try Harness.stored(
            [Self.uncovered(3)],
            Harness.Setup(other: [
                // g0 (1 of 10 lines) and g1 (none of 4) tie on 4 unkilled:
                // g1 comes first by line coverage, not by subject.
                Self.function(1, of: 10, Harness.planted(3, .survived) + Harness.planted(1, .notCovered)),
                Self.uncovered(4),
                Self.function(1, of: 4, Harness.planted(3, .notCovered)),
                Self.function(0, of: 4, Harness.planted(1, .killed) + Harness.planted(3, .notCovered)),
                Self.uncovered(5)
            ], testLines: ["Lib": 30, "Other": 1])
        )
        let signal = try Harness.signal(.genuinelyUnderTested, of: snapshot)

        #expect(signal.leftOut == nil)
        #expect(signal.candidates == 6)
        #expect(signal.items.map(\.subject) == [4, 1, 0].map(Harness.otherKey))
        #expect(signal.items.map(\.score) == [5, 4, 4])
        #expect(signal.rule == GenuinelyUnderTested.rule(thresholds: SignalThresholds()) + "; "
            + "2 production modules = 1 with low test code + 1 without; 1 = 0 with no test code + 1 below the "
            + "project's ratio; 6 production functions = 6 with coverage data + 0 without; 6 = 6 with at least 3 "
            + "scored mutants + 0 with fewer + 0 with only build errors + 0 with none + 0 without results (0 "
            + "unresolved, 0 unlisted); 6 = 5 at most 20% covered + 1 more; 5 = 3 listed + 1 under 20% in a module "
            + "whose test code isn't low + 1 not under 20%")
        #expect(Harness.unbalanced(signal.rule).isEmpty)
        let ratio = try #require(signal.items.first?.ratio)
        let own = try #require(ratio.moduleLines)
        let project = try #require(ratio.projectLines)
        #expect(ratio.module == "Other")
        #expect(own.testLines * project.productionLines < project.testLines * own.productionLines)
        #expect(signal.items.first?.mutation?.functionScore == MutationScore(killed: 0, scored: 5))
        #expect(signal.items.first?.coverage?.lines == Harness.lines(0, of: Harness.functionLines))
    }

    @Test("""
        results that don't list code no test ran leave it out with its thresholds stated, while weak tests is \
        computed and says such functions aren't judged
        """)
    func notCoveredUnlisted() throws {
        let snapshot = try Harness.stored(
            [Harness.covered(Harness.planted(1, .killed) + Harness.planted(3, .survived))],
            Harness.Setup(listsNotCovered: false)
        )
        let thresholds = SignalThresholds(limits: ["genuinely-under-tested": ["score": 25]])
        let signal = try Harness.signal(.genuinelyUnderTested, of: snapshot, thresholds: thresholds)
        let weak = try Harness.signal(.weakTests, of: snapshot)

        #expect(signal.leftOut == "the mutation results don't list code no test ran (a SwiftMutator build before "
            + "13f96a46), so low scores can't be told from missing ones")
        #expect(signal.rule == GenuinelyUnderTested.rule(thresholds: thresholds))
        #expect(signal.rule.contains("function score under 25%"))
        #expect(signal.items.isEmpty && signal.candidates == 0)
        #expect(weak.leftOut == nil && weak.items.count == 1)
        #expect(weak.rule.hasSuffix("; " + WeakTests.notListedNote))
    }

    @Test("""
        one production module whose tests are measured lists nothing and says so first; the ratio, when set, \
        makes its test code low below it; a module with no test code is low without it
        """)
    func singleModule() throws {
        let tested = try Harness.stored([Self.uncovered(3)])
        let untested = try Harness.stored([Self.uncovered(3)], Harness.Setup(testLines: [:]))
        let ratio = SignalThresholds(limits: ["genuinely-under-tested": ["ratio": 100]])

        let plain = try Harness.signal(.genuinelyUnderTested, of: tested)
        #expect(plain.items.isEmpty && plain.candidates == 1)
        #expect(plain.rule.contains(
            "; one production module: its ratio is the project's, so no function can be listed; 1 production module "
                + "= 0 with low test code + 1 without; 0 = 0 with no test code + 0 below the project's ratio; "
        ))
        #expect(plain.rule.hasSuffix(
            "1 = 0 listed + 1 under 20% in a module whose test code isn't low + 0 not under 20%"
        ))

        let configured = try Harness.signal(.genuinelyUnderTested, of: tested, thresholds: ratio)
        #expect(configured.items.map(\.subject) == [Harness.key(0)])
        #expect(configured.rule.contains("below the project's or below 100 test lines per production line (tests"))
        #expect(configured.rule.contains(
            "; 1 production module = 1 with low test code + 0 without; 1 = 0 with no test code + 0 below the "
                + "project's ratio + 1 below 100 test lines per production line alone; "
        ))
        #expect(configured.rule.contains("one production module:") == false)

        let bare = try Harness.signal(.genuinelyUnderTested, of: untested)
        #expect(bare.items.map(\.subject) == [Harness.key(0)])
        #expect(bare.items.first?.ratio?.moduleLines == SignalItem.RatioLines(testLines: 0, productionLines: 4))
        #expect(bare.rule.contains("1 production module = 1 with low test code + 0 without; 1 = 1 with no test code"))
        #expect(bare.rule.contains("one production module:") == false)
        for signal in [plain, configured, bare] {
            #expect(Harness.unbalanced(signal.rule).isEmpty)
        }
    }

    /// `Lib`'s one function has 4 production lines and its test 10 test
    /// lines (2.5 per production line), so a ratio of 2.5 is met exactly.
    @Test("""
        with the ratio set, one production module at or above it lists nothing and the funnel doesn't say nothing \
        can be listed: a module exactly at the ratio isn't below it
        """)
    func singleModuleWithRatio() throws {
        let tested = try Harness.stored([Self.uncovered(3)])
        let below = SignalThresholds(limits: ["genuinely-under-tested": ["ratio": 0.25]])
        let equal = SignalThresholds(limits: ["genuinely-under-tested": ["ratio": 2.5]])

        let above = try Harness.signal(.genuinelyUnderTested, of: tested, thresholds: below)
        let exact = try Harness.signal(.genuinelyUnderTested, of: tested, thresholds: equal)

        let lines = ModuleRatios(tested, ratio: nil).payload("Lib").moduleLines
        #expect(lines == SignalItem.RatioLines(testLines: 10, productionLines: 4))
        for (signal, ratio) in [(above, "0.25"), (exact, "2.5")] {
            #expect(signal.items.isEmpty && signal.candidates == 1)
            #expect(signal.rule.contains("one production module:") == false)
            #expect(signal.rule.contains(
                "; 1 production module = 0 with low test code + 1 without; 0 = 0 with no test code + 0 below the "
                    + "project's ratio + 0 below \(ratio) test lines per production line alone; "
            ))
            #expect(signal.rule.hasSuffix(
                "1 = 0 listed + 1 under 20% in a module whose test code isn't low + 0 not under 20%"
            ))
            #expect(Harness.unbalanced(signal.rule).isEmpty)
        }
    }

    @Test("""
        the rule and funnel print the limits compared, in full: a small ratio, a long fractional percent and a ratio \
        too large for an Int
        """)
    func limitsInFull() throws {
        let tested = try Harness.stored([Self.uncovered(3)])
        let small = SignalThresholds(limits: ["genuinely-under-tested": ["ratio": 0.004, "coverage": 33.333]])
        let large = SignalThresholds(limits: ["genuinely-under-tested": ["ratio": 1e19]])

        let signal = try Harness.signal(.genuinelyUnderTested, of: tested, thresholds: small)
        #expect(signal.rule.contains("at most 33.333% of lines covered"))
        #expect(signal.rule.contains("below the project's or below 0.004 test lines per production line (tests"))
        #expect(signal.rule.contains("+ 0 below 0.004 test lines per production line alone; "))
        #expect(signal.rule.contains("1 = 1 at most 33.333% covered + 0 more"))
        let huge = try Harness.signal(.genuinelyUnderTested, of: tested, thresholds: large)
        #expect(huge.items.map(\.subject) == [Harness.key(0)])
        #expect(huge.rule.contains("+ 1 below 10000000000000000000 test lines per production line alone; "))
        for computed in [signal, huge] {
            #expect(Harness.unbalanced(computed.rule).isEmpty)
        }
    }

    @Test("set thresholds change membership: 25% covered and 30% killed list a function the defaults count apart")
    func overrides() throws {
        let snapshot = try Harness.stored(
            [Self.function(1, of: 4, Harness.planted(1, .killed) + Harness.planted(3, .survived))],
            Harness.Setup(testLines: [:])
        )
        let thresholds = SignalThresholds(limits: ["genuinely-under-tested": ["coverage": 25, "score": 30]])

        #expect(try Harness.signal(.genuinelyUnderTested, of: snapshot).items.isEmpty)
        let signal = try Harness.signal(.genuinelyUnderTested, of: snapshot, thresholds: thresholds)
        #expect(signal.items.map(\.subject) == [Harness.key(0)] && signal.items.first?.score == 3)
        #expect(signal.rule.contains("at most 25% of lines covered, function score under 30%"))
    }
}
