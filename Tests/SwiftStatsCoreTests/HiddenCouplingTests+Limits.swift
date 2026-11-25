//
//  HiddenCouplingTests+Limits.swift
//  SwiftStatsCoreTests
//
//  Hidden coupling's limits (M7, design §8.1) on `CouplingSignalHarness`'
//  small package: support and confidence compared at their edges, with
//  the `min_support` note, and a confidence equal to a decimal limit with
//  no exact binary value compared exactly.
//

@testable import SwiftStatsCore
import Testing

/// Hidden coupling's limits at their edges.
extension HiddenCouplingTests {
    @Test("""
        the limits compare at their edges: support 2 against limits 3 and 2, support 3 against 4, and 3 of 6 \
        changes against confidence 49, 50, 50.5 and 51; a support limit below the history's min_support says so \
        after the funnel
        """)
    func limitEdges() throws {
        let made = try TemporaryStore("HiddenCoupling")
        defer { made.remove() }
        let plain = try Harness.plain(in: made.store)
        var facts = Harness.Facts()
        facts.pairs = [
            try Harness.pair("loneOne", "loneTwo", support: 3, changes: (6, 7), in: plain),
            try Harness.pair("loneOne", "loneThree", support: 2, changes: (2, 2), in: plain)
        ]
        let snapshot = try Harness.stored(facts, in: made.store)
        let verdicts = { (support: Double, confidence: Double) in
            try Harness.verdicts(snapshot, thresholds: Self.limits(support: support, confidence: confidence))
        }
        let note = "; pairs exist only at or above history.coupling.min_support (3)"
        let lowered = try Harness.signal(snapshot, thresholds: Self.limits(support: 2, confidence: 50))
        let standard = try Harness.signal(snapshot, thresholds: SignalThresholds())

        #expect(try verdicts(3, 50) == [.listed, .belowLimits])
        #expect(try verdicts(2, 50) == [.listed, .listed])
        #expect(try verdicts(4, 50) == [.belowLimits, .belowLimits])
        #expect(try verdicts(3, 49) == [.listed, .belowLimits])
        #expect(try verdicts(3, 50.5) == [.belowLimits, .belowLimits])
        #expect(try verdicts(3, 51) == [.belowLimits, .belowLimits])
        #expect(lowered.rule.hasSuffix("; 2 = 2 listed + 0 below the limits" + note))
        #expect(lowered.rule.hasPrefix(HiddenCoupling.rule(thresholds: Self.limits(support: 2, confidence: 50))))
        #expect(standard.rule.hasSuffix("; 2 = 1 listed + 1 below the limits"))
        #expect(HiddenCoupling.minimumSupport(snapshot) == Harness.minimumSupport)
        #expect(HiddenCoupling.note(HiddenCoupling.Limits(SignalThresholds()), minimumSupport: nil).isEmpty)
    }

    @Test("""
        a confidence equal to a limit with no exact binary value reaches it: 161 of 250 changes reaches 64.4 and \
        not 64.41, 7 of 625 reaches 1.12 and not 1.13, though floating point puts both limits' products above \
        the support's
        """)
    func decimalLimitEdges() throws {
        let made = try TemporaryStore("HiddenCoupling")
        defer { made.remove() }
        let plain = try Harness.plain(in: made.store)
        var facts = Harness.Facts()
        facts.pairs = [
            try Harness.pair("loneOne", "loneTwo", support: 161, changes: (300, 250), in: plain),
            try Harness.pair("loneOne", "loneThree", support: 7, changes: (625, 700), in: plain)
        ]
        let snapshot = try Harness.stored(facts, in: made.store)
        let verdicts = { (confidence: Double) in
            try Harness.verdicts(snapshot, thresholds: Self.limits(support: 3, confidence: confidence))
        }

        #expect(64.4 * 250 > 16_100 && 1.12 * 625 > 700)
        #expect(try verdicts(64.4) == [.listed, .belowLimits])
        #expect(try verdicts(64.41) == [.belowLimits, .belowLimits])
        #expect(try verdicts(1.12) == [.listed, .listed])
        #expect(try verdicts(1.13) == [.listed, .belowLimits])
    }
}
