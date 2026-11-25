//
//  FakeToolchain+Build.swift
//  SwiftStatsCoreTests
//
//  `FakeToolchain`'s build scenario (M7, design §13 step 3b), so the T1
//  build's tests never build anything: the same proxy `swift`, answering
//  `-print-target-info`, and a toolchain `swift` that answers `--version`,
//  answers `package … describe` with a description (the Index fixture's
//  recorded `describe.json`), and acts out `build`: it runs the scenario's
//  script, writes the recorded standard output and standard error, makes
//  `out/v5/units` and the root package's intermediates folder when asked,
//  appends a line to the scanned files named, waits to be stopped in its
//  slow mode, and exits as scripted, or exits 64 at `--build-system` as a
//  toolchain without Swift Build does. Every call's arguments are logged.
//  In recorded text `@ROOT@` becomes the package root (the working
//  directory, as `pwd -P` gives it), `@BUILD@` the build directory, and
//  the other recording placeholders paths in the toolchain directory.
//

import Foundation
@testable import SwiftStatsCore

extension FakeToolchain {
    /// What the fake build's tools do.
    struct BuildScenario {
        /// What `swift package describe` prints, placeholders restored.
        var describe: String
        /// What the build writes to standard output.
        var stdout: String
        /// What the build writes to standard error.
        var stderr: String
        /// The build's exit status.
        var status: Int32 = 0
        /// Shell commands the build runs first, in the package root, with
        /// `$scratch` the build directory.
        var script = ""
        /// Whether the build makes `out/v5/units`.
        var makesStore = true
        /// The name of the intermediates folder the build makes
        /// (`out/Intermediates.noindex/<name>.build`); nil for none.
        var intermediates: String? = "IndexFixture"
        /// The files, relative to the package root, the build appends a
        /// line to.
        var edits: [String] = []
        /// Whether the build exits 64 at `--build-system`, as a toolchain
        /// without Swift Build does.
        var rejectsBuildSystem = false
        /// Whether the build, after its output, waits until it is stopped.
        var slow = false
        /// The steps that fail with status 1: `print-target-info`,
        /// `version` (the toolchain `swift`'s) and `describe`.
        var failing: Set<String> = []
    }

    /// The toolchain `swift` of the build scenario: `--version`,
    /// `package … describe` and `build`; anything else is unexpected.
    static let buildSwiftScript = """
        restored() {
            if [ -f "$1" ]; then
                sed "s|@ROOT@|$root|g; s|@BUILD@|$2|g; s|@PARENT@|$(dirname "$root")|g; \
        s|@DEP@|$top/IndexDep|g; s|@TOOLCHAIN@|$top|g; s|@DEVELOPER@|$top/Developer|g; s|@TMP@|$top/tmp|g" "$1"
            fi
        }
        case "$1" in
            --version)
                if fails version; then echo "error: unable to print the version" >&2; exit 1; fi
                printf 'Apple Swift version 9.9 (fake)\\nTarget: arm64-apple-macosx14.0\\n'
                exit 0 ;;
            package)
                if fails describe; then echo "error: unable to describe" >&2; exit 1; fi
                restored "$s/describe" "$3"
                exit 0 ;;
        esac
        if [ "$1" != "build" ]; then echo "unexpected: $*" >&2; exit 99; fi
        scratch=""
        previous=""
        for argument in "$@"; do
            if [ "$previous" = "--scratch-path" ]; then scratch="$argument"; fi
            if [ "$argument" = "--build-system" ] && [ -f "$s/rejects-build-system" ]; then
                echo "error: The value 'swiftbuild' is invalid for '--build-system <build-system>'. \
        Please provide one of 'native' and 'xcode'." >&2
                echo "Usage: swift build <options>" >&2
                exit 64
            fi
            previous="$argument"
        done
        . "$s/script"
        restored "$s/stdout" "$scratch"
        restored "$s/stderr" "$scratch" >&2
        if [ -f "$s/makes-store" ]; then mkdir -p "$scratch/out/v5/units"; fi
        if [ -f "$s/intermediates" ]; then
            mkdir -p "$scratch/out/Intermediates.noindex/$(cat "$s/intermediates").build"
        fi
        while IFS= read -r edited; do
            printf '// edited during the build\\n' >> "$edited"
        done < "$s/edits"
        if [ -f "$s/slow" ]; then
            echo $$ > "$top/pid"
            : > "$top/ready"
            while :; do /bin/sleep 1; done
        fi
        exit "$(cat "$s/status")"

        """

    /// How often `waitingBuild(within:)` looks for the slow build, in
    /// seconds.
    private static let buildPollInterval: TimeInterval = 0.05

    /// The scenario of the Index fixture's recorded first build: its
    /// description, standard output and standard error, exiting 0.
    static func recordedBuild() throws -> BuildScenario {
        BuildScenario(
            describe: try IndexFixture.text("describe.json"),
            stdout: try IndexFixture.text("build.stdout"),
            stderr: try IndexFixture.text("build.stderr")
        )
    }

    /// A new toolchain acting out the build `scenario`.
    static func make(build scenario: BuildScenario) throws -> Self {
        let toolchain = Self(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("FakeToolchain-\(UUID().uuidString)")
        )
        let scenarioDirectory = toolchain.directory.appendingPathComponent("scenario")
        try FileManager.default.createDirectory(at: scenarioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: toolchain.directory.appendingPathComponent("usr/lib/swift"),
            withIntermediateDirectories: true
        )
        var files = [
            "describe": scenario.describe,
            "stdout": scenario.stdout,
            "stderr": scenario.stderr,
            "status": "\(scenario.status)",
            "script": scenario.script,
            "edits": scenario.edits.map { $0 + "\n" }.joined()
        ]
        let flags = [
            "makes-store": scenario.makesStore,
            "rejects-build-system": scenario.rejectsBuildSystem,
            "slow": scenario.slow
        ]
        for (flag, set) in flags where set {
            files[flag] = ""
        }
        if let intermediates = scenario.intermediates {
            files["intermediates"] = intermediates
        }
        for step in scenario.failing {
            files["fail-\(step)"] = ""
        }
        for (name, contents) in files {
            try contents.write(to: scenarioDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try toolchain.writeScript("proxy/swift", body: FakeToolchainScripts.proxy, log: "proxy")
        try toolchain.writeScript("usr/bin/swift", body: buildSwiftScript, log: "swift")
        return toolchain
    }

    /// The process identifier of the slow build once it waits to be
    /// stopped, or nil when it doesn't within `timeout` seconds.
    func waitingBuild(within timeout: TimeInterval) -> pid_t? {
        let ready = directory.appendingPathComponent("ready")
        let deadline = Date().addingTimeInterval(timeout)
        while FileManager.default.fileExists(atPath: ready.path) == false {
            guard Date() < deadline else {
                return nil
            }
            Thread.sleep(forTimeInterval: Self.buildPollInterval)
        }
        let text = (try? String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)) ?? ""
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Writes the executable script at `path` in the toolchain: the
    /// shared prologue, logging its calls as `log`, then `body`.
    private func writeScript(_ path: String, body: String, log: String) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (FakeToolchainScripts.prologue(top: directory.path, tool: log) + body)
            .write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
