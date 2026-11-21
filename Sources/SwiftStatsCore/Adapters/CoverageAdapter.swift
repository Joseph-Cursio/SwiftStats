//
//  CoverageAdapter.swift
//  SwiftStatsCore
//
//  The coverage collector (M5, PRD §7.8). It runs only when asked for with
//  `scan --coverage`, never in `backfill` or in `diff`'s exports, since it
//  builds and runs the package's tests: minutes on a real package. It uses
//  the toolchain of the `swift` it resolves (`collectors.coverage.path`,
//  else PATH), building in `<package>/.swiftstats/coverage-build`, which
//  persists between runs, and `collectors.coverage.arguments` may add
//  `--skip <regex>` pairs to `swift test`. Failing tests don't fail it: it
//  merges the test processes' profiles itself. It fails when the build
//  fails, when there is no test bundle, when a bundle's XCTest or Swift
//  Testing process wrote no profile (it crashed or was killed), or when the
//  export isn't one SwiftStats reads; the scan maps the export it decodes.
//

import Foundation

/// The coverage collector's name, statuses, options and run.
enum CoverageAdapter {
    /// The collector's name in a snapshot.
    static let name = "coverage"
    /// Why a scan that didn't ask for coverage skipped it.
    static let notRequestedReason = "not requested; scan --coverage runs it"
    /// The build directory's name, in the package's `.swiftstats`.
    static let buildDirectory = "coverage-build"
    /// The first option: how the tests run, with the build directory as
    /// the package sees it.
    static let invocation = "swift test --enable-code-coverage --scratch-path .swiftstats/coverage-build"

    /// The build identity of a run whose `swift` prints `versionLine`
    /// first for `--version`: the toolchain is the tool, as for the
    /// dependency graph.
    static func identity(versionLine: String) -> String {
        "swift:\(versionLine)"
    }

    /// The options of a run on the package at `root` whose `swift test`
    /// gets `arguments`, before its tools are known: how the tests run,
    /// the arguments verbatim and the toolchain pin.
    static func options(arguments: [String], root: URL) -> [String] {
        [
            invocation,
            "arguments: " + (arguments.isEmpty ? "none" : arguments.joined(separator: " ")),
            SwiftInferCopy.toolchainOption(root: root)
        ]
    }

    /// Runs the tests of the package at `root` with coverage, using the
    /// toolchain `swift` resolves to there, with `arguments` added to
    /// `swift test`; `locator` finds `xcrun` when the toolchain lacks the
    /// LLVM tools.
    static func run(swift: URL, root: URL, arguments: [String], locator: ToolLocator) -> CoverageRun {
        let initial = options(arguments: arguments, root: root)
        var toolchain: CoverageToolchain?
        let (outcome, milliseconds) = Stopwatch.time {
            Result {
                let build = try StoreLocation.ignoreDirectory(packageRoot: root).appendingPathComponent(buildDirectory)
                let found = try CoverageToolchain.discover(
                    swift: swift,
                    command: CoverageCommand(root: root, build: build, toolchain: nil),
                    locator: locator
                )
                toolchain = found
                let command = CoverageCommand(root: root, build: build, toolchain: found.directory)
                let profiles = try CoverageSession(toolchain: found, arguments: arguments, command: command).collect()
                return (profiles, try CoverageExport.read(profiles.export))
            }
        }
        let known = initial + (toolchain?.options ?? [])
        switch outcome {
        case let .success((profiles, export)):
            let passed = profiles.testStatus == 0
            let status = CollectorStatus(
                name: name,
                state: .ran,
                version: toolchain?.covVersion,
                reason: passed ? nil : failingReason(profiles),
                options: known + ["tests: " + (passed ? "passed" : "failing"), "map: " + CoverageMapper.rule]
            )
            return CoverageRun(
                status: status,
                executable: toolchain?.swift,
                identity: toolchain.map { identity(versionLine: $0.swiftVersion) },
                milliseconds: milliseconds,
                profiles: profiles,
                export: export
            )

        case .failure(let error):
            let reason = (error as? CoverageFailure)?.description
                ?? SwiftInferTargetRun.reason(for: error, replacing: [(root, CoverageCommand.packagePlaceholder)])
            return CoverageRun(
                status: CollectorStatus(name: name, state: .failed, version: nil, reason: reason, options: known),
                executable: toolchain?.swift ?? swift,
                identity: toolchain.map { identity(versionLine: $0.swiftVersion) },
                milliseconds: milliseconds,
                profiles: nil,
                export: nil
            )
        }
    }

    /// Why a run whose tests failed still ran: its coverage comes from the
    /// test processes' profiles, which may miss a process that crashed
    /// after an exit test's child wrote a profile in its name.
    private static func failingReason(_ profiles: CoverageProfiles) -> String {
        "tests failing (swift test exited \(profiles.testStatus)); coverage merged from the test processes' profiles"
            + (profiles.hasExtraProfiles
                ? "; a test process may have crashed after an exit test, so coverage may be incomplete"
                : "")
    }
}
