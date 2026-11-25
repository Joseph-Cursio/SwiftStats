import Foundation
@testable import SwiftStatsCore
import Testing

/// M7's signals' limits under `signals:` (design §8): only hidden coupling
/// takes any, `support` a whole number of commits from 1 to a million (3
/// by default) and `confidence` a percent from 0 to 100 (50 by default);
/// dead but tested and test-only production code take none, so a key for
/// either is unknown; anything else is an error naming the key. A report
/// lists hidden coupling's limits in effect.
@Suite("Index signal configuration")
struct IndexSignalConfigurationTests {
    /// The error parsing `text`, or nil when it parses.
    private static func error(_ text: String) -> ScanError? {
        do {
            _ = try SwiftStatsConfiguration.parse(text, path: "c.yml")
            return nil
        } catch {
            return error as? ScanError
        }
    }

    @Test("""
        hidden coupling's limits default to support 3 and confidence 50, set ones replace them one by one, \
        and the edges of each range are valid
        """)
    func limits() throws {
        let defaults = SignalThresholds()
        let support = try SwiftStatsConfiguration.parse(
            "signals:\n  hidden-coupling:\n    support: 1000000\n",
            path: "c.yml"
        ).signals
        let confidence = try SwiftStatsConfiguration.parse(
            "signals:\n  hidden-coupling:\n    support: 1\n    confidence: 0\n",
            path: "c.yml"
        ).signals
        let whole = try SwiftStatsConfiguration.parse(
            "signals:\n  hidden-coupling:\n    confidence: 100\n",
            path: "c.yml"
        ).signals

        #expect(defaults.limit("support", of: "hidden-coupling") == 3)
        #expect(defaults.limit("confidence", of: "hidden-coupling") == 50)
        #expect(support.limits == ["hidden-coupling": ["support": 1_000_000]])
        #expect(support.limit("confidence", of: "hidden-coupling") == 50)
        #expect(confidence.limits == ["hidden-coupling": ["support": 1, "confidence": 0]])
        #expect(whole.limit("confidence", of: "hidden-coupling") == 100)
        #expect(whole.limit("support", of: "hidden-coupling") == 3)
        #expect(try SwiftStatsConfiguration.parse("signals:\n  hidden-coupling:\n", path: "c.yml").signals == defaults)
        #expect(SignalThresholds.limitKinds["dead-but-tested"] == nil)
        #expect(SignalThresholds.limitKinds["test-only-production"] == nil)
    }

    @Test("a report lists hidden coupling's limits in effect, set or default, and none for the other two")
    func reported() {
        let configured = SignalThresholds(limits: ["hidden-coupling": ["confidence": 75]])

        let defaults = ReportThresholds(SignalThresholds())
        let set = ReportThresholds(configured)

        #expect(defaults.limits["hidden-coupling"] == ["support": 3, "confidence": 50])
        #expect(set.limits["hidden-coupling"] == ["support": 3, "confidence": 75])
        #expect(defaults.limits["dead-but-tested"] == nil && defaults.limits["test-only-production"] == nil)
    }

    @Test(
        "invalid hidden-coupling limits and keys of the signals that take none are errors naming the key",
        arguments: [
            (
                "signals:\n  hidden-coupling:\n    support: 0\n",
                "`signals.hidden-coupling.support` must be a whole number from 1 to 1000000"
            ),
            (
                "signals:\n  hidden-coupling:\n    support: 2.5\n",
                "`signals.hidden-coupling.support` must be a whole number from 1 to 1000000"
            ),
            (
                "signals:\n  hidden-coupling:\n    support: 1000001\n",
                "`signals.hidden-coupling.support` must be a whole number from 1 to 1000000"
            ),
            (
                "signals:\n  hidden-coupling:\n    confidence: 100.5\n",
                "`signals.hidden-coupling.confidence` must be a percent from 0 to 100"
            ),
            (
                "signals:\n  hidden-coupling:\n    confidence: -1\n",
                "`signals.hidden-coupling.confidence` must be a percent from 0 to 100"
            ),
            (
                "signals:\n  hidden-coupling:\n    confidence: half\n",
                "`signals.hidden-coupling.confidence` must be a percent from 0 to 100"
            ),
            (
                "signals:\n  hidden-coupling:\n    mutants: 3\n",
                "unknown key(s) under `signals.hidden-coupling`: mutants"
            ),
            (
                "signals:\n  hidden-coupling:\n    threshold: 5\n",
                "unknown key(s) under `signals.hidden-coupling`: threshold"
            ),
            ("signals:\n  hidden-coupling: 3\n", "`signals.hidden-coupling` must be a mapping"),
            ("signals:\n  dead-but-tested:\n    mutants: 1\n", "unknown key(s) under `signals`: dead-but-tested"),
            (
                "signals:\n  test-only-production:\n    support: 1\n",
                "unknown key(s) under `signals`: test-only-production"
            )
        ]
    )
    func invalid(text: String, message: String) {
        #expect(Self.error(text) == .configurationInvalid("c.yml", message))
    }
}
