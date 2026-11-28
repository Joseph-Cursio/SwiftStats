import Foundation
@testable import SwiftStatsCore
import Testing

/// The mutation signals' limits under `signals:` (M6, design §7): each of
/// weak tests, genuinely under-tested and uneven clone mutation takes its
/// own keys, percents from 0 to 100, a fewest number of mutants from 1 to a
/// million, genuinely under-tested an optional ratio above 0 (unset by default),
/// and uneven clone mutation's `high` above its `low`; anything else is an
/// error naming the key.
@Suite("Mutation signal configuration")
struct MutationSignalConfigurationTests {
    /// A faulty limit of each limit-taking signal, as `limit: value`, and
    /// the reason it is refused.
    private static let faultySignals: [String: (setting: String, reason: String)] = [
        "genuinely-under-tested": ("coverage: 200", "`signals.genuinely-under-tested.coverage` \(percentReason)"),
        "hidden-coupling": ("confidence: 200", "`signals.hidden-coupling.confidence` \(percentReason)"),
        "uneven-clone-mutation": ("high: 200", "`signals.uneven-clone-mutation.high` \(percentReason)"),
        "weak-tests": ("coverage: 200", "`signals.weak-tests.coverage` \(percentReason)")
    ]
    /// A faulty value of each of genuinely under-tested's limits, and the
    /// reason it is refused.
    private static let faultyLimits: [String: (value: String, reason: String)] = [
        "coverage": ("200", percentReason),
        "mutants": ("0", "must be a whole number from 1 to 1000000"),
        "ratio": ("0", "must be a number above 0"),
        "score": ("200", percentReason)
    ]
    /// Why a percent limit is refused.
    private static let percentReason = "must be a percent from 0 to 100"

    /// Every pair of `names`, sorted, the alphabetically first first.
    private static func pairs(_ names: [String]) -> [(String, String)] {
        let sorted = names.sorted()
        return sorted.indices.flatMap { first in
            sorted[(first + 1)...].map { (sorted[first], $0) }
        }
    }

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
        the limits default to the design's, set ones replace them one by one beside the ranked thresholds, and \
        genuinely under-tested's ratio is unset unless set
        """)
    func limits() throws {
        let text = """
            signals:
              hotspot:
                threshold: 5
              weak-tests:
                coverage: 75
                score: 49.5
              genuinely-under-tested:
                mutants: 1000000
                ratio: 0.25
              uneven-clone-mutation:
                high: 90
                low: 0
                mutants: 1
            """
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")
        let defaults = SignalThresholds()
        let signals = configuration.signals

        #expect(defaults.limit("coverage", of: "weak-tests") == 80)
        #expect(defaults.limit("score", of: "weak-tests") == 50)
        #expect(defaults.limit("mutants", of: "weak-tests") == 3)
        #expect(defaults.limit("coverage", of: "genuinely-under-tested") == 20)
        #expect(defaults.limit("score", of: "genuinely-under-tested") == 20)
        #expect(defaults.limit("mutants", of: "genuinely-under-tested") == 3)
        #expect(defaults.limit("ratio", of: "genuinely-under-tested") == nil)
        #expect(defaults.limit("high", of: "uneven-clone-mutation") == 80)
        #expect(defaults.limit("low", of: "uneven-clone-mutation") == 20)
        #expect(defaults.limit("mutants", of: "uneven-clone-mutation") == 2)
        #expect(signals.percent(for: "hotspot") == 5)
        #expect(signals.limits == [
            "weak-tests": ["coverage": 75, "score": 49.5],
            "genuinely-under-tested": ["mutants": 1_000_000, "ratio": 0.25],
            "uneven-clone-mutation": ["high": 90, "low": 0, "mutants": 1]
        ])
        #expect(signals.limit("coverage", of: "weak-tests") == 75)
        #expect(signals.limit("mutants", of: "weak-tests") == 3)
        #expect(signals.limit("coverage", of: "genuinely-under-tested") == 20)
        #expect(signals.limit("ratio", of: "genuinely-under-tested") == 0.25)
        #expect(try SwiftStatsConfiguration.parse("signals:\n  weak-tests:\n", path: "c.yml").signals == defaults)
    }

    @Test(
        "invalid limits, unknown keys and a high not above the low are errors naming the key",
        arguments: [
            (
                "signals:\n  weak-tests:\n    coverage: 101\n",
                "`signals.weak-tests.coverage` must be a percent from 0 to 100"
            ),
            ("signals:\n  weak-tests:\n    score: -1\n", "`signals.weak-tests.score` must be a percent from 0 to 100"),
            (
                "signals:\n  weak-tests:\n    score: half\n",
                "`signals.weak-tests.score` must be a percent from 0 to 100"
            ),
            (
                "signals:\n  weak-tests:\n    mutants: 0\n",
                "`signals.weak-tests.mutants` must be a whole number from 1 to 1000000"
            ),
            (
                "signals:\n  genuinely-under-tested:\n    mutants: 2.5\n",
                "`signals.genuinely-under-tested.mutants` must be a whole number from 1 to 1000000"
            ),
            (
                "signals:\n  weak-tests:\n    mutants: 1000001\n",
                "`signals.weak-tests.mutants` must be a whole number from 1 to 1000000"
            ),
            (
                "signals:\n  uneven-clone-mutation:\n    mutants: 9223372036854775807\n",
                "`signals.uneven-clone-mutation.mutants` must be a whole number from 1 to 1000000"
            ),
            (
                "signals:\n  genuinely-under-tested:\n    ratio: 0\n",
                "`signals.genuinely-under-tested.ratio` must be a number above 0"
            ),
            (
                "signals:\n  genuinely-under-tested:\n    ratio: .inf\n",
                "`signals.genuinely-under-tested.ratio` must be a number above 0"
            ),
            ("signals:\n  weak-tests:\n    ratio: 0.5\n", "unknown key(s) under `signals.weak-tests`: ratio"),
            ("signals:\n  weak-tests:\n    threshold: 5\n", "unknown key(s) under `signals.weak-tests`: threshold"),
            ("signals:\n  weak-test:\n    score: 5\n", "unknown key(s) under `signals`: weak-test"),
            ("signals:\n  weak-tests: 5\n", "`signals.weak-tests` must be a mapping"),
            (
                "signals:\n  uneven-clone-mutation:\n    low: 80\n",
                "`signals.uneven-clone-mutation.high` must be above `signals.uneven-clone-mutation.low`"
            ),
            (
                "signals:\n  uneven-clone-mutation:\n    high: 30\n    low: 40\n",
                "`signals.uneven-clone-mutation.high` must be above `signals.uneven-clone-mutation.low`"
            )
        ]
    )
    func invalid(text: String, message: String) {
        #expect(Self.error(text) == .configurationInvalid("c.yml", message))
    }

    @Test(
        "of two faulty limit-taking signals, written last first, the error names the first alphabetically",
        arguments: pairs(Array(faultySignals.keys))
    )
    func firstFaultySignal(first: String, second: String) throws {
        let faults = try [second, first].map { signal in
            (signal, try #require(Self.faultySignals[signal]))
        }
        let text = "signals:\n" + faults.map { "  \($0.0):\n    \($0.1.setting)\n" }.joined()
        let reason = try #require(Self.faultySignals[first]).reason

        #expect(Self.error(text) == .configurationInvalid("c.yml", reason))
    }

    @Test(
        "of two faulty limits of genuinely under-tested, written last first, the error names the first alphabetically",
        arguments: pairs(Array(faultyLimits.keys))
    )
    func firstFaultyLimit(first: String, second: String) throws {
        let faults = try [second, first].map { limit in
            (limit, try #require(Self.faultyLimits[limit]))
        }
        let text = "signals:\n  genuinely-under-tested:\n" + faults.map { "    \($0.0): \($0.1.value)\n" }.joined()
        let reason = "`signals.genuinely-under-tested.\(first)` " + (try #require(Self.faultyLimits[first]).reason)

        #expect(Self.error(text) == .configurationInvalid("c.yml", reason))
    }
}
