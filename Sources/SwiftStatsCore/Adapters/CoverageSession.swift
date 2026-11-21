//
//  CoverageSession.swift
//  SwiftStatsCore
//
//  One coverage run's commands (M5), in order: find the bin path of the
//  build directory, clear what an earlier run left there (its profiles,
//  whose stale copies a failed build would otherwise leave to be read, and
//  its test bundles, of which a removed test target's would stay), build
//  the tests with coverage, check that each bundle is a test target, as
//  the toolchain's own `swift package describe` gives them (the manifest
//  the build read, which may not be the one the scan's `swift` read: a
//  `Package@swift-<version>.swift` or `#if compiler(…)` can add a test
//  target), run them on that build, accepting every exit status, then
//  merge each bundle's profiles, tie them to their bundle and export every
//  bundle over all of them.
//  Every SwiftPM command passes `--build-system swiftbuild`, so the layout
//  is Swift Build's, one bundle per test target, whatever the toolchain's
//  default (native up to Swift 6.3, which makes one merged bundle); a
//  toolchain that doesn't accept it fails the run, saying so. SwiftPM
//  resolves dependencies in the package root whatever the scratch path,
//  writing `Package.resolved`, so the run keeps that file's bytes (or its
//  absence) before the first command and puts them back when it ends,
//  whether it succeeds or fails, and `ScratchRegistry` does on an
//  interruption.
//

import Foundation

/// The commands of one coverage run.
struct CoverageSession {
    /// The file a run's merged profiles are written to, in the build
    /// directory.
    static let mergedFile = "swiftstats.profdata"
    /// The file the export is written to, in the build directory.
    static let exportFile = "swiftstats-export.json"
    /// The extension of a merged profile.
    private static let profdataExtension = "profdata"
    /// The extension of a test bundle.
    private static let bundleExtension = "xctest"
    /// The build system every `swift` command of the run asks for.
    static let buildSystemFlags = ["--build-system", "swiftbuild"]
    /// The lockfile SwiftPM writes in the package root.
    static let lockfileName = "Package.resolved"

    /// The toolchain's tools.
    let toolchain: CoverageToolchain
    /// What `swift test` gets after its own flags: `--skip <regex>` pairs.
    let arguments: [String]
    /// Runs the commands in the package root and words their failures.
    let command: CoverageCommand

    /// The flags every `swift` command of the run passes for its build.
    private var buildFlags: [String] {
        Self.buildSystemFlags + ["--enable-code-coverage", "--scratch-path", command.build.path]
    }

    /// The test bundles in `bin`, each with its executable, sorted by
    /// name; a failure when there is none.
    private static func bundles(in bin: URL) throws -> [(name: String, executable: URL)] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: bin.path)) ?? []
        let bundles = entries.filter { $0.hasSuffix(".\(bundleExtension)") }.sorted().compactMap { entry in
            let name = String(entry.dropLast(bundleExtension.count + 1))
            let executable = bin.appendingPathComponent(entry).appendingPathComponent("Contents/MacOS/\(name)")
            return FileManager.default.fileExists(atPath: executable.path) ? (name, executable) : nil
        }
        guard bundles.isEmpty == false else {
            throw CoverageFailure(description: "no test bundle was built (the package has no test targets)")
        }
        return bundles
    }

    /// The raw profiles in `codecov`, sorted by name; a failure when one's
    /// name doesn't follow the grammar.
    private static func profiles(in codecov: URL) throws -> [CoverageProfile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: codecov.path)) ?? []
        return try names.filter { $0.hasSuffix(".\(CoverageProfile.fileExtension)") }.sorted().map { name in
            let url = codecov.appendingPathComponent(name)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard let profile = CoverageProfile(url: url, size: size) else {
                throw CoverageFailure(
                    description: "the profile \(name) doesn't follow "
                        + "<XCTest|Swift Testing><signature>_<n>.<pid>.profraw"
                )
            }
            return profile
        }
    }

    /// Runs the tests with coverage and returns their profiles' data,
    /// leaving the package's `Package.resolved` as it found it.
    func collect() throws -> CoverageProfiles {
        let lockfile: PreservedFile
        do {
            lockfile = try PreservedFile(url: command.root.appendingPathComponent(Self.lockfileName))
        } catch {
            let reason = SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
            throw CoverageFailure(
                description: "could not read \(Self.lockfileName) to put it back afterwards: \(reason)"
            )
        }
        ScratchRegistry.shared.preserve(lockfile)
        let collected = Result { try collectProfiles() }
        do {
            try ScratchRegistry.shared.putBack(lockfile)
        } catch {
            let reason = SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
            throw CoverageFailure(description: "could not put \(Self.lockfileName) back as it was: \(reason)")
        }
        return try collected.get()
    }

    /// Runs the tests with coverage and returns their profiles' data.
    private func collectProfiles() throws -> CoverageProfiles {
        let bin = try binPath()
        try clearStale(bin: bin)
        let build = ["build", "--build-tests"] + buildFlags
        _ = try command.run(toolchain.swift, build, display: command.display(toolchain.swift, build))
        let bundles = try Self.bundles(in: bin)
        if let unknown = CoverageBundles.unknownBundles(bundles.map(\.name), testTargets: try testTargets()) {
            throw CoverageFailure(description: unknown)
        }
        let test = ["test", "--skip-build"] + buildFlags + arguments
        let testDisplay = command.display(toolchain.swift, test)
        let tested = try command.runToEnd(toolchain.swift, test, display: testDisplay)
        let profiles = try Self.profiles(in: bin.appendingPathComponent("codecov"))
        if tested.status != 0, profiles.isEmpty {
            throw command.failure(testDisplay, output: tested)
        }
        let groups = try group(profiles)
        let owners = CoverageBundles.owners(
            of: groups,
            bundles: bundles.map(\.name),
            demangled: try demangled(CoverageBundles.runnerCandidates(in: groups))
        )
        if let problem = CoverageBundles.problem(groups: groups, owners: owners, bundles: bundles.map(\.name)) {
            throw CoverageFailure(description: problem)
        }
        let export = try export(groups.flatMap(\.written), bundles: bundles.map(\.executable))
        var counts: [String: [String: Int64]] = [:]
        for group in groups {
            if let bundle = owners[group.signature] {
                counts[bundle] = group.counts
            }
        }
        return CoverageProfiles(
            export: export,
            bundles: bundles.map(\.name),
            testStatus: tested.status,
            hasExtraProfiles: groups.contains(where: \.hasExtraProfiles),
            counts: counts
        )
    }

    /// The bin path of the build directory, as `swift build --show-bin-path`
    /// prints it; a failure that says so when the toolchain's `swift`
    /// doesn't accept `--build-system swiftbuild`.
    private func binPath() throws -> URL {
        let invocation = ["build", "--show-bin-path"] + buildFlags
        let display = command.display(toolchain.swift, invocation)
        let output = try command.runToEnd(toolchain.swift, invocation, display: display)
        guard output.status == 0 else {
            let failure = command.failure(display, output: output)
            guard output.errorText.contains(Self.buildSystemFlags[0]) else {
                throw failure
            }
            throw CoverageFailure(
                description: "this toolchain's swift doesn't accept `\(Self.buildSystemFlags.joined(separator: " "))`, "
                    + "and coverage needs Swift Build's test bundles, one per test target (Swift 6.2 or later): "
                    + failure.description
            )
        }
        let line = (String(bytes: output.output, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.isEmpty == false }
        guard let line else {
            throw CoverageFailure(description: "`\(display)` printed no path")
        }
        return URL(fileURLWithPath: line)
    }

    /// The package's test targets, by name, as the toolchain's own
    /// `swift package describe` gives them, its caches in the build
    /// directory.
    private func testTargets() throws -> [String] {
        let invocation = ["package", "--scratch-path", command.build.path, "describe", "--type", "json"]
        let display = command.display(toolchain.swift, invocation)
        let output = try command.run(toolchain.swift, invocation, display: display)
        do {
            return try JSONDecoder().decode(DescribedPackage.self, from: output.output).targets
                .filter { $0.type == "test" }
                .map(\.name)
        } catch {
            let reason = SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
            throw CoverageFailure(
                description: "`\(display)` printed no package description SwiftStats reads: \(reason)"
            )
        }
    }

    /// Removes the profiles and test bundles an earlier run left in `bin`,
    /// and SwiftStats' own files in the build directory.
    private func clearStale(bin: URL) throws {
        let fileManager = FileManager.default
        var stale = [bin.appendingPathComponent("codecov")]
        stale += ((try? fileManager.contentsOfDirectory(atPath: bin.path)) ?? [])
            .filter { $0.hasSuffix(".\(Self.bundleExtension)") }
            .map { bin.appendingPathComponent($0) }
        stale += ((try? fileManager.contentsOfDirectory(atPath: command.build.path)) ?? [])
            .filter { name in
                name == Self.mergedFile || name == Self.exportFile
                    || (name.hasSuffix(".\(Self.profdataExtension)")
                        && name.dropLast(Self.profdataExtension.count + 1).allSatisfy(\.isNumber))
            }
            .map { command.build.appendingPathComponent($0) }
        for url in stale where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                let reason = SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
                throw CoverageFailure(description: "could not clear what an earlier run left: \(reason)")
            }
        }
    }

    /// `profiles` grouped by signature, sorted by it, each with the entry
    /// counts of its non-empty profiles merged into `<build>/<signature>.profdata`.
    private func group(_ profiles: [CoverageProfile]) throws -> [CoverageGroup] {
        try Dictionary(grouping: profiles, by: \.signature).sorted { $0.key < $1.key }.map { signature, members in
            let written = members.filter { $0.isEmpty == false }
            guard written.isEmpty == false else {
                return CoverageGroup(signature: signature, profiles: members, counts: [:])
            }
            let merged = command.build.appendingPathComponent("\(signature).\(Self.profdataExtension)")
            try merge(written, into: merged)
            let invocation = ["show", "--all-functions", "--counts", merged.path]
            let display = command.display(toolchain.profdata, invocation)
            let shown = try command.run(toolchain.profdata, invocation, display: display)
            let counts = ProfileShow.counts(String(bytes: shown.output, encoding: .utf8) ?? "")
            return CoverageGroup(signature: signature, profiles: members, counts: counts)
        }
    }

    /// Merges `profiles` with `-sparse` into `output`.
    private func merge(_ profiles: [CoverageProfile], into output: URL) throws {
        let shown = ["merge", "-sparse", "(\(profiles.count) profiles)", "-o", output.path]
        let display = command.display(toolchain.profdata, shown)
        _ = try command.run(
            toolchain.profdata,
            ["merge", "-sparse"] + profiles.map(\.url.path) + ["-o", output.path],
            display: display
        )
    }

    /// The demangled text of each of `names`, from one
    /// `swift demangle --compact` call; empty when there are none, or when
    /// it doesn't print one line per name.
    private func demangled(_ names: [String]) throws -> [String: String] {
        guard names.isEmpty == false else {
            return [:]
        }
        let display = command.display(toolchain.swift, ["demangle", "--compact", "(\(names.count) names)"])
        let output = try command.run(toolchain.swift, ["demangle", "--compact"] + names, display: display)
        let lines = (String(bytes: output.output, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline)
        guard lines.count == names.count else {
            return [:]
        }
        return Dictionary(zip(names, lines.map(String.init))) { first, _ in first }
    }

    /// Merges `profiles` into the build directory's `swiftstats.profdata`
    /// and exports `bundles` over it into `swiftstats-export.json`, which
    /// it returns: the first bundle as the binary, the others as objects,
    /// since SwiftPM's own export holds one bundle only.
    private func export(_ profiles: [CoverageProfile], bundles: [URL]) throws -> URL {
        let merged = command.build.appendingPathComponent(Self.mergedFile)
        try merge(profiles.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }, into: merged)
        let export = command.build.appendingPathComponent(Self.exportFile)
        let objects = bundles.dropFirst().flatMap { ["-object", $0.path] }
        let invocation = ["export", "-instr-profile", merged.path] + bundles.prefix(1).map(\.path) + objects
        let shown = ["export", "-instr-profile", merged.path, "(\(bundles.count) bundles)"]
        let display = command.display(toolchain.cov, shown)
        try command.run(toolchain.cov, invocation, writingOutputTo: export, display: display)
        return export
    }
}
