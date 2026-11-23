//
//  MutationAdapter.swift
//  SwiftStatsCore
//
//  The SwiftMutator collector (M6, design §1). It runs only when asked for
//  with `scan --mutation`, never in `backfill`, in `diff`'s scans of other
//  revisions or with `--rerun`, since a full run takes most of an hour on a
//  real package. Every scan lists its status, so a snapshot says how to run
//  it when it didn't. Its test command's `swift` is the coverage
//  collector's (`collectors.coverage.path`, else PATH, whether or not
//  coverage is enabled). Its identity is the SwiftMutator build its
//  results file's header names, and its options are the settings that can
//  change outcomes, the same for a full and a `--since` run of the same
//  settings: never the workers, the mode, the base or a date.
//

import Foundation

/// The SwiftMutator collector's name, executable, statuses and options.
enum MutationAdapter {
    /// The collector's name in a snapshot and in `.swiftstats.yml`.
    static let name = "swiftmutator"
    /// SwiftMutator's executable on PATH.
    static let executableName = "swift-mutator"
    /// Why a scan that didn't ask for mutation testing skipped it.
    static let notRequestedReason = "not requested; scan --mutation runs it"
    /// Why `scan --mutation --since` is refused while the merge isn't
    /// built (M6 step 6 replaces it).
    static let sinceNotBuiltReason = "--since is not built yet; run scan --mutation for a full run"
    /// The first option: how SwiftMutator runs, as the package sees it.
    static let invocation = "swift-mutator run -c .swiftstats/mutation/muter.conf.yml --skip-update-check"
    /// The largest number of seconds written as a whole number.
    private static let wholeSecondsLimit = 1e15

    /// `seconds` as an option and an argument write it: a whole number
    /// without a fraction (`30`), else as Swift prints it (`2.5`).
    static func seconds(_ seconds: Double) -> String {
        guard seconds.rounded() == seconds, abs(seconds) < wholeSecondsLimit else {
            return String(seconds)
        }
        return String(Int(seconds))
    }

    /// The `swift` whose `test` SwiftMutator runs, for the package at
    /// `root`: `collectors.coverage.path`, else `swift` on PATH, whether
    /// or not the coverage collector is enabled; a skip when there is none.
    static func testSwift(configuration: SwiftStatsConfiguration, locator: ToolLocator, root: URL) -> ToolResolution {
        let coverage = configuration.collectors[CoverageAdapter.name]
        return ToolResolution.resolve(
            CoverageAdapter.name,
            executable: "swift",
            settings: coverage.map { CollectorSettings(enabled: true, path: $0.path) },
            locator: locator,
            root: root
        )
    }

    /// The options known before a run of the package at `root` under
    /// `settings`: how SwiftMutator runs, the arguments verbatim, the time
    /// limit and the toolchain pin.
    static func options(settings: CollectorSettings?, root: URL) -> [String] {
        let arguments = settings?.arguments ?? []
        return [
            invocation,
            "arguments: " + (arguments.isEmpty ? "none" : arguments.joined(separator: " ")),
            "timeout: " + (settings?.timeout.map(seconds) ?? "default"),
            SwiftInferCopy.toolchainOption(root: root)
        ]
    }

    /// The options a results file's header adds, from its `facts`: the
    /// toolchain's first version line, the test executable's and SDK
    /// environment's hashes, the operators and coverage.
    static func options(of facts: MutationRunFacts) -> [String] {
        let toolchain = facts.testCommandVersion?.split(whereSeparator: \.isNewline).first.map(String.init)
        return [
            "toolchain: " + (toolchain ?? "unrecorded"),
            "test executable: " + (facts.testExecutableSHA256.map { "sha256:\($0)" } ?? "unrecorded"),
            "sdk environment: " + sdkEnvironment(facts.sdkEnvironment),
            "operators: " + facts.operators.sorted().joined(separator: ", "),
            "coverage: " + (facts.skipCoverage ? "off" : "on")
        ]
    }

    /// The build identity a results file's header names: `sha256:` and
    /// SwiftMutator's executable's SHA-256; nil when it records none.
    static func identity(of facts: MutationRunFacts) -> String? {
        facts.executableSHA256.map { "sha256:\($0)" }
    }

    /// `environment` (`DEVELOPER_DIR`, `SDKROOT`, `TOOLCHAINS` as the
    /// header records them) as an option: `none` when empty, else
    /// `sha256:` and the hash of its `NAME=value` lines sorted by name,
    /// since the paths it holds are never recorded.
    static func sdkEnvironment(_ environment: [String: String]) -> String {
        guard environment.isEmpty == false else {
            return "none"
        }
        let lines = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)\n" }.joined()
        return "sha256:" + ContentHash.sha256(Data(lines.utf8))
    }
}
