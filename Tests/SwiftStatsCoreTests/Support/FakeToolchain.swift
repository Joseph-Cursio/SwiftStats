//
//  FakeToolchain.swift
//  SwiftStatsCoreTests
//
//  A toolchain of shell scripts standing in for the coverage collector's
//  tools (M5), so its tests never build or run real tests: a proxy `swift`
//  outside the toolchain, standing in for swiftly's, which answers only
//  `-print-target-info`, naming the toolchain's `usr/lib/swift`; the
//  toolchain's own `usr/bin/swift`, which runs everything else; and
//  `llvm-profdata` and `llvm-cov` beside it, or out of the toolchain behind
//  a fake `xcrun`.
//  A scenario says what each command does; the recorded one serves what
//  the real tools printed for the Coverage fixture (`Recorded/`, made by
//  `Scripts/record-coverage-fixture.sh`), with `@ROOT@` and `@BUILD@` put
//  back as the package root and the build directory of the run.
//

import Foundation
@testable import SwiftStatsCore

/// A fake toolchain for the coverage collector.
struct FakeToolchain {
    /// What the fake tools do.
    struct Scenario {
        /// The test bundles a successful `swift build --build-tests` makes.
        var bundles: [String]
        /// The profiles `swift test` writes into the bin path's `codecov`,
        /// each with its size in bytes.
        var profiles: [(name: String, size: Int)]
        /// The entry counts `llvm-profdata show` prints, by signature.
        var shows: [String: String]
        /// `<mangled>\t<demangled>` lines `swift demangle` answers from;
        /// a name not listed comes back as it is.
        var demangled: String
        /// What `llvm-cov export` prints.
        var export: String
        /// `swift build --build-tests`'s exit status.
        var buildStatus: Int32 = 0
        /// What `swift build --build-tests` writes to standard error.
        var buildError = ""
        /// `swift test`'s exit status.
        var testStatus: Int32 = 0
        /// What `swift test` writes to standard error.
        var testError = ""
        /// The steps that fail with status 1: `print-target-info`,
        /// `version` (the toolchain `swift`'s), `show-bin-path`, `merge`,
        /// `show`, `export`, `demangle`, `xcrun`.
        var failing: Set<String> = []
        /// The steps that print nothing and succeed: `show-bin-path`,
        /// `xcrun`.
        var silent: Set<String> = []
        /// What the proxy prints for `-print-target-info` in place of the
        /// toolchain's runtime resource path, when set.
        var targetInfo: String?
        /// Whether the toolchain has its own `swift` beside its runtime
        /// resources.
        var swiftInToolchain = true
        /// Whether `llvm-profdata` and `llvm-cov` sit beside `swift`; when
        /// not, only `xcrun --find` names them.
        var llvmInToolchain = true
        /// Shell commands `swift test` runs before it writes its profiles,
        /// with `$top` the toolchain directory.
        var testScript = ""
    }

    /// The Coverage fixture's recorded tool output.
    static let recordedDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Coverage/Recorded")

    /// The toolchain's directory.
    let directory: URL

    /// The toolchain's `swift`.
    var swift: URL {
        directory.appendingPathComponent("usr/bin/swift")
    }

    /// The `swift` a run resolves, outside the toolchain: it answers only
    /// `-print-target-info`, and logs its calls as `proxy`.
    var proxy: URL {
        directory.appendingPathComponent("proxy/swift")
    }

    /// The fake `xcrun`, which names the LLVM tools kept out of the
    /// toolchain.
    var xcrun: URL {
        directory.appendingPathComponent("xcrun")
    }

    /// A locator that finds the fake `xcrun` and nothing else.
    var locator: ToolLocator {
        let found = xcrun
        return ToolLocator { name in name == "xcrun" ? found : nil }
    }

    /// The scenario of the fixture's recorded run: its bundles, profiles,
    /// `show` texts, runner names and export, every test passing.
    static func recorded() throws -> Scenario {
        let read = { (name: String) in
            try String(contentsOf: recordedDirectory.appendingPathComponent(name), encoding: .utf8)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: recordedDirectory.path)
        var shows: [String: String] = [:]
        for file in files where file.hasPrefix("show-") && file.hasSuffix(".txt") {
            shows[String(file.dropFirst("show-".count).dropLast(".txt".count))] = try read(file)
        }
        return Scenario(
            bundles: try read("bundles.txt").split(separator: "\n").map(String.init),
            profiles: try read("profiles.txt").split(separator: "\n").map { (String($0), 1) },
            shows: shows,
            demangled: try read("demangled.txt"),
            export: try read("export.json")
        )
    }

    /// The signatures of the recorded run's profiles, sorted: the
    /// fixture's `ProbeTests` bundle's first, then `SwiftTestKitTests`'.
    static func recordedSignatures() throws -> [String] {
        let profiles = try recorded().profiles.map(\.name)
        return Array(Set(profiles.compactMap { name in
            CoverageProfile(url: URL(fileURLWithPath: name), size: 1)?.signature
        })).sorted()
    }

    /// A new toolchain acting out `scenario`.
    static func make(_ scenario: Scenario) throws -> Self {
        let name = "FakeToolchain-\(UUID().uuidString)"
        let toolchain = Self(directory: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        try toolchain.write(scenario)
        return toolchain
    }

    /// The calls of `tool` (`proxy`, `swift`, `llvm-profdata`, `llvm-cov`
    /// or `xcrun`), each its arguments joined by tabs.
    func calls(of tool: String) -> [String] {
        let log = directory.appendingPathComponent("\(tool).log")
        return ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    /// Removes the toolchain.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes the scripts and `scenario`'s files.
    private func write(_ scenario: Scenario) throws {
        let scenarioDirectory = directory.appendingPathComponent("scenario")
        try FileManager.default.createDirectory(at: scenarioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("usr/lib/swift"),
            withIntermediateDirectories: true
        )
        var files = [
            "bundles": scenario.bundles.map { $0 + "\n" }.joined(),
            "profiles": scenario.profiles.map { "\($0.name)\t\($0.size)\n" }.joined(),
            "demangled": scenario.demangled,
            "export": scenario.export,
            "build-status": "\(scenario.buildStatus)",
            "build-error": scenario.buildError,
            "test-status": "\(scenario.testStatus)",
            "test-error": scenario.testError,
            "test-script": scenario.testScript
        ]
        for (signature, text) in scenario.shows {
            files["show-\(signature)"] = text
        }
        for step in scenario.failing {
            files["fail-\(step)"] = ""
        }
        for step in scenario.silent {
            files["silent-\(step)"] = ""
        }
        if let info = scenario.targetInfo {
            files["target-info"] = info
        }
        for (name, contents) in files {
            try contents.write(to: scenarioDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let llvm = scenario.llvmInToolchain ? "usr/bin" : "xcode"
        try script("proxy/swift", body: FakeToolchainScripts.proxy, log: "proxy")
        if scenario.swiftInToolchain {
            try script("usr/bin/swift", body: FakeToolchainScripts.swift)
        }
        try script("\(llvm)/llvm-profdata", body: FakeToolchainScripts.profdata)
        try script("\(llvm)/llvm-cov", body: FakeToolchainScripts.cov)
        try script("xcrun", body: FakeToolchainScripts.xcrun)
    }

    /// Writes the executable script at `path` in the toolchain: the
    /// shared prologue, logging its calls as `log` (by default its file
    /// name), then `body`.
    private func script(_ path: String, body: String, log: String? = nil) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = FakeToolchainScripts.prologue(top: directory.path, tool: log ?? url.lastPathComponent) + body
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
