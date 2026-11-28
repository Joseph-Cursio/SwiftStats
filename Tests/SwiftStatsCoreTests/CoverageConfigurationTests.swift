import Foundation
@testable import SwiftStatsCore
import Testing

/// The coverage collector's configuration (M5): `collectors.coverage`
/// takes `arguments`, which allow only `--skip <regex>` pairs, no other
/// collector but swiftmutator (M6) takes any, and the build directory
/// under `.swiftstats` is
/// ignored by git whatever the store.
@Suite("Coverage configuration")
struct CoverageConfigurationTests {
    /// The configuration `text` holds, or the error parsing it gives.
    private static func parsed(_ text: String) -> Result<SwiftStatsConfiguration, ScanError> {
        Result { try SwiftStatsConfiguration.parse(text, path: "c.yml") }.mapError { error in
            error as? ScanError ?? .configurationInvalid("c.yml", "\(error)")
        }
    }

    /// The configuration error for `collectors.coverage.arguments` listing `tokens`.
    private static func argumentsError(_ tokens: [String]) -> ScanError? {
        let list = tokens.map { "\"\($0)\"" }.joined(separator: ", ")
        guard case .failure(let error) = parsed("collectors:\n  coverage:\n    arguments: [\(list)]\n") else {
            return nil
        }
        return error
    }

    @Test("collectors.coverage takes enabled, path and --skip <regex> pairs as arguments")
    func configuration() throws {
        let text = """
        collectors:
          coverage:
            enabled: true
            path: tools/swift
            arguments: ["--skip", "MeasuredTests|PerformanceTests", "--skip", "^Slow"]
        """
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")
        let bare = try SwiftStatsConfiguration.parse("collectors:\n  coverage:\n", path: "c.yml")

        #expect(configuration.collectors["coverage"] == CollectorSettings(
            enabled: true,
            path: "tools/swift",
            arguments: ["--skip", "MeasuredTests|PerformanceTests", "--skip", "^Slow"]
        ))
        #expect(configuration.unusedKeys.isEmpty)
        #expect(bare.collectors["coverage"] == CollectorSettings(enabled: true, path: nil, arguments: []))
    }

    @Test("any other coverage argument is an error naming it and the allowed form")
    func argumentAllowlist() {
        let allowed = "only `--skip <regex>` pairs are allowed"
        let key = "`collectors.coverage.arguments`"
        let notAllowed = ["--disable-xctest", "--disable-swift-testing", "--filter", "-c", "--parallel", "--skip=A"]
        for token in notAllowed {
            #expect(
                Self.argumentsError([token, "release"])
                    == .configurationInvalid("c.yml", "\(key): `\(token)` is not allowed; \(allowed)")
            )
        }
        #expect(
            Self.argumentsError(["--skip", "A", "--sanitize", "thread"])
                == .configurationInvalid("c.yml", "\(key): `--sanitize` is not allowed; \(allowed)")
        )
        #expect(
            Self.argumentsError(["--skip"])
                == .configurationInvalid("c.yml", "\(key): `--skip` needs a regex after it")
        )
        #expect(
            Self.argumentsError(["--skip", "--filter"])
                == .configurationInvalid("c.yml", "\(key): `--filter` is not a regex for `--skip`; \(allowed)")
        )
        #expect(
            Self.argumentsError(["--skip", ""])
                == .configurationInvalid("c.yml", "\(key): `` is not a regex for `--skip`; \(allowed)")
        )
        for null in ["null", "~", "NULL"] {
            let result = Self.parsed("collectors:\n  coverage:\n    arguments: [\"--skip\", \(null)]\n")
            guard case .failure(let error) = result else {
                Issue.record("a null regex `\(null)` should not parse")
                continue
            }
            #expect(error == .configurationInvalid("c.yml", "\(key) must be a list of strings; \(allowed)"))
        }
        let quoted = Self.parsed("collectors:\n  coverage:\n    arguments: [\"--skip\", \"null\"]\n")
        #expect((try? quoted.get().collectors["coverage"]?.arguments) == ["--skip", "null"])
        let notAList = Self.parsed("collectors:\n  coverage:\n    arguments: --skip A\n")
        guard case .failure(let error) = notAList else {
            Issue.record("a string for arguments should not parse")
            return
        }
        #expect(error == .configurationInvalid("c.yml", "\(key) must be a list of strings; \(allowed)"))
    }

    @Test("only the coverage and swiftmutator collectors take arguments")
    func argumentsElsewhere() {
        for name in ["swiftlint", "dependencies", "swiftinferproperties"] {
            let result = Self.parsed("collectors:\n  \(name):\n    arguments: [\"--skip\", \"A\"]\n")
            guard case .failure(let error) = result else {
                Issue.record("arguments under \(name) should not parse")
                continue
            }
            let message = "`collectors.\(name).arguments`: only the coverage and swiftmutator collectors take arguments"
            #expect(error == .configurationInvalid("c.yml", message))
        }
    }

    @Test("ignoreDirectory makes .swiftstats ignore itself, keeping a .gitignore already there")
    func ignoreDirectory() throws {
        let root = try SnapshotHarness.temporaryDirectory("Ignore")
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = try SnapshotHarness.temporaryDirectory("Ignore")
        defer { try? FileManager.default.removeItem(at: kept) }
        let existing = kept.appendingPathComponent(".swiftstats")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let ignoreFile = existing.appendingPathComponent(".gitignore")
        try "stats.sqlite\n".write(to: ignoreFile, atomically: true, encoding: .utf8)

        let directory = try StoreLocation.ignoreDirectory(packageRoot: root)
        try StoreLocation.ignoreDirectory(packageRoot: kept)

        #expect(directory.path == root.appendingPathComponent(".swiftstats").path)
        let ignore = try String(contentsOf: directory.appendingPathComponent(".gitignore"), encoding: .utf8)
        #expect(ignore == "*\n")
        let keptIgnore = try String(contentsOf: ignoreFile, encoding: .utf8)
        #expect(keptIgnore == "stats.sqlite\n")
    }
}
