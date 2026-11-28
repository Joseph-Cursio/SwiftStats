import Foundation
@testable import SwiftStatsCore
import Testing

/// The SwiftMutator collector's configuration (M6, design §1.1):
/// `collectors.swiftmutator` takes `enabled`, `path`, the coverage
/// collector's `--skip <regex>` allowlist as `arguments`, and `options`
/// holding `workers` and `timeout`; any other key under `options` is an
/// error, while `options` under any other collector is still accepted with
/// a warning.
@Suite("Mutation configuration")
struct MutationConfigurationTests {
    /// The configuration `text` holds, or the error parsing it gives.
    private static func parsed(_ text: String) -> Result<SwiftStatsConfiguration, ScanError> {
        Result { try SwiftStatsConfiguration.parse(text, path: "c.yml") }.mapError { error in
            error as? ScanError ?? .configurationInvalid("c.yml", "\(error)")
        }
    }

    /// The error parsing a swiftmutator entry whose `options` line reads
    /// `options`, or nil when it parses.
    private static func optionsError(_ options: String) -> ScanError? {
        guard case .failure(let error) = parsed("collectors:\n  swiftmutator:\n    options: \(options)\n") else {
            return nil
        }
        return error
    }

    @Test("collectors.swiftmutator takes enabled, path, --skip <regex> pairs as arguments, workers and timeout")
    func configuration() throws {
        let text = """
        collectors:
          swiftmutator:
            enabled: true
            path: tools/swift-mutator
            arguments: ["--skip", "chainClassifiesInLinearTime|selfInClassesScale"]
            options:
              workers: 3
              timeout: 42.5
        """
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")
        let bare = try SwiftStatsConfiguration.parse("collectors:\n  swiftmutator:\n", path: "c.yml")
        let wholeSeconds = try SwiftStatsConfiguration.parse(
            "collectors:\n  swiftmutator:\n    options:\n      timeout: 86400\n",
            path: "c.yml"
        )
        let nullOptions = try SwiftStatsConfiguration.parse(
            "collectors:\n  swiftmutator:\n    options:\n",
            path: "c.yml"
        )

        #expect(configuration.collectors["swiftmutator"] == CollectorSettings(
            enabled: true,
            path: "tools/swift-mutator",
            arguments: ["--skip", "chainClassifiesInLinearTime|selfInClassesScale"],
            workers: 3,
            timeout: 42.5
        ))
        #expect(configuration.unusedKeys.isEmpty)
        #expect(bare.collectors["swiftmutator"] == CollectorSettings(enabled: true, path: nil))
        #expect(wholeSeconds.collectors["swiftmutator"]?.timeout == 86_400)
        #expect(wholeSeconds.collectors["swiftmutator"]?.workers == nil)
        #expect(nullOptions.collectors["swiftmutator"] == CollectorSettings(enabled: true, path: nil))
        #expect(nullOptions.unusedKeys.isEmpty)
    }

    @Test("swiftmutator's arguments take the coverage collector's allowlist, with its errors")
    func argumentAllowlist() {
        let allowed = "only `--skip <regex>` pairs are allowed"
        let key = "`collectors.swiftmutator.arguments`"
        let cases: [(String, String)] = [
            ("[\"--filter\", \"A\"]", "\(key): `--filter` is not allowed; \(allowed)"),
            ("[\"--skip\"]", "\(key): `--skip` needs a regex after it"),
            ("[\"--skip\", \"-x\"]", "\(key): `-x` is not a regex for `--skip`; \(allowed)"),
            ("[\"--skip\", null]", "\(key) must be a list of strings; \(allowed)"),
            ("--skip A", "\(key) must be a list of strings; \(allowed)")
        ]
        for (arguments, message) in cases {
            let result = Self.parsed("collectors:\n  swiftmutator:\n    arguments: \(arguments)\n")
            guard case .failure(let error) = result else {
                Issue.record("arguments \(arguments) should not parse")
                continue
            }
            #expect(error == .configurationInvalid("c.yml", message), "\(arguments)")
        }
    }

    @Test("workers must be a whole number of at least 1, naming the key")
    func workersErrors() {
        let message = "`collectors.swiftmutator.options.workers` must be a whole number of at least 1"
        for value in ["0", "-1", "2.5", "many", "true", "[2]"] {
            #expect(
                Self.optionsError("{workers: \(value)}") == .configurationInvalid("c.yml", message),
                "workers: \(value)"
            )
        }
        #expect(Self.optionsError("{workers: 1}") == nil)
        #expect(Self.optionsError("{workers: ~}") == nil)
    }

    @Test(
        """
        workers written in base 60 reads as YAML 1.1 reads it, plain only, underscores dropped, the sign applying \
        to the whole sum, ten places at most, and one quoted, of more places, or whose value, a place's value or \
        its sign would pass Int, is refused naming the key, not a trap (design B30)
        """,
        arguments: [
            ("1:30", 90), ("+1:30", 90), ("1:-5", 55), ("2:0:0", 7_200),
            ("1:0:0:0:0:0:0:0:0:0", 10_077_696_000_000_000), ("1:0:0:0:0:0:0:0:0:0:0", nil),
            ("9223372036854775807:0", nil), ("153722867280912931:0", nil),
            ("--153722867280912930:-8", nil), ("01:30", nil), ("1::30", nil),
            ("'1:30'", nil), ("\"1:30\"", nil), ("1_0:30", 630), ("1_000:0", 60_000),
            ("-1:30", nil), ("-1:-120", 60), ("+01:30", nil), ("+0:30", nil), ("+-153722867280912930:-9", nil)
        ]
    )
    func baseSixtyWorkers(text: String, workers: Int?) throws {
        let parsed = Self.parsed("collectors:\n  swiftmutator:\n    options:\n      workers: \(text)\n")

        guard let workers else {
            let message = "`collectors.swiftmutator.options.workers` must be a whole number of at least 1"
            #expect(throws: ScanError.configurationInvalid("c.yml", message)) { try parsed.get() }
            return
        }
        #expect(try parsed.get().collectors["swiftmutator"]?.workers == workers)
    }

    @Test("timeout must be a number of seconds above 0 and at most a day, naming the key")
    func timeoutErrors() {
        let message = "`collectors.swiftmutator.options.timeout` must be a number of seconds above 0 "
            + "and at most 86400"
        for value in ["0", "-3", "86400.5", "86401", ".inf", ".nan", "soon", "false"] {
            #expect(
                Self.optionsError("{timeout: \(value)}") == .configurationInvalid("c.yml", message),
                "timeout: \(value)"
            )
        }
        #expect(Self.optionsError("{timeout: 0.25}") == nil)
        #expect(Self.optionsError("{timeout: 20}") == nil)
    }

    @Test("any other key under swiftmutator's options is an error naming it, as is options that isn't a mapping")
    func unknownOptions() {
        #expect(Self.optionsError("{workers: 2, stopAtFirstFailure: false, excludes: []}") == .configurationInvalid(
            "c.yml",
            "unknown key(s): collectors.swiftmutator.options.excludes, "
                + "collectors.swiftmutator.options.stopAtFirstFailure"
        ))
        #expect(Self.optionsError("[--workers, 2]") == .configurationInvalid(
            "c.yml",
            "`collectors.swiftmutator.options` must be a mapping of workers and timeout"
        ))
    }

    @Test("options under any other collector is still accepted with a warning, and swiftmutator's isn't warned")
    func optionsElsewhere() throws {
        let text = """
        collectors:
          coverage:
            options: {workers: 2}
          swiftlint:
            options: [--strict]
          swiftmutator:
            options: {workers: 2}
        """
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")

        #expect(configuration.unusedKeys == ["collectors.coverage.options", "collectors.swiftlint.options"])
        #expect(configuration.collectors["coverage"]?.workers == nil)
        #expect(configuration.collectors["swiftmutator"]?.workers == 2)
        let warnings = PackageScanner.unusedKeyWarnings(configuration).map(\.message)
        #expect(warnings == [
            "`collectors.coverage.options` is accepted but not used yet; it has no effect on this scan",
            "`collectors.swiftlint.options` is accepted but not used yet; it has no effect on this scan"
        ])
    }
}
