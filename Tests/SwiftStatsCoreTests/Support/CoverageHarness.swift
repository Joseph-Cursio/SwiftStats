//
//  CoverageHarness.swift
//  SwiftStatsCoreTests
//
//  Runs the coverage collector (M5) with a `FakeToolchain` on a fresh
//  package, for the coverage run's tests.
//

import Foundation
@testable import SwiftStatsCore

/// Runs the coverage collector against fake toolchains.
enum CoverageHarness {
    /// What a run left: its result, and the toolchain and package it ran
    /// with, for their logs and files.
    struct Outcome {
        /// The run.
        let run: CoverageRun
        /// The fake toolchain.
        let toolchain: FakeToolchain
        /// The package root.
        let root: URL

        /// The run's build directory.
        var build: URL {
            root.appendingPathComponent(".swiftstats/coverage-build")
        }

        /// The bin path of the run's build directory.
        var bin: URL {
            build.appendingPathComponent("out/Products/Debug")
        }
    }

    /// The bin path of the build directory of the package at `root`.
    static func bin(of root: URL) -> URL {
        root.appendingPathComponent(".swiftstats/coverage-build/out/Products/Debug")
    }

    /// The recorded scenario's signature for `bundle`: the one whose
    /// `show` text names its test module.
    static func signature(of bundle: String, in scenario: FakeToolchain.Scenario) -> String {
        scenario.shows.first { $0.value.contains("$s\(bundle.count)\(bundle)") }?.key ?? ""
    }

    /// Runs the collector with a fake toolchain acting out `scenario` on a
    /// package whose `swift test` gets `arguments`, after `prepare` has run
    /// on the package root, and passes what it left to `check`.
    static func run(
        _ scenario: FakeToolchain.Scenario,
        arguments: [String],
        prepare: (URL) throws -> Void,
        check: (Outcome) throws -> Void
    ) throws {
        let toolchain = try FakeToolchain.make(scenario)
        defer { toolchain.remove() }
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer { package.remove() }
        try prepare(package.root)
        let run = CoverageAdapter.run(
            swift: toolchain.proxy,
            root: package.root,
            arguments: arguments,
            locator: toolchain.locator
        )
        try check(Outcome(run: run, toolchain: toolchain, root: package.root))
    }

    /// Runs the collector as `run(_:arguments:prepare:check:)` does, with
    /// no arguments and nothing prepared.
    static func run(_ scenario: FakeToolchain.Scenario, check: (Outcome) throws -> Void) throws {
        try run(scenario, arguments: [], prepare: { _ in /* Nothing to prepare. */ }, check: check)
    }

    /// The reason a run acting out `scenario` failed for, or nil when it
    /// didn't fail.
    static func failure(_ scenario: FakeToolchain.Scenario) throws -> String? {
        var reason: String?
        try run(scenario) { outcome in
            reason = outcome.run.status.state == .failed ? outcome.run.status.reason : nil
        }
        return reason
    }
}
