//
//  FakeMutator.swift
//  SwiftStatsCoreTests
//
//  A `swift-mutator` and a `swift` of shell scripts standing in for the
//  SwiftMutator collector's tools (M6, design §11 step 3b), so its tests
//  never build a package or mutate it. `swift-mutator run` writes the
//  scenario's results file into SwiftMutator's log folder beside the
//  project it runs in, `<parent>/<name>_muter_logs/Nov 21, 2026 at 7:32
//  AM/`, a locale-style name with spaces and a comma, prints the
//  scenario's log (with its `💾 … in <path>` line), and exits with the
//  scenario's status or raises its signal; `report` writes the scenario's
//  JSON report to its `-o` file, or exits with the report status alone.
//  `@ROOT@` stands for the project, `@PARENT@` for its parent, `@NAME@`
//  for its name and `@FOLDER@` for the run folder's name, as in the recordings
//  (`Scripts/record-mutation-fixture.sh`). The fake `swift` answers `build
//  --build-tests` with the scenario's output (`@ROOT@` the project) and
//  status, adding a line to `.build/builds.txt` so a test can follow the
//  build between runs. Each
//  tool logs its arguments (tab-separated, one call a line), its working
//  directory, `NO_COLOR` and whether standard input was empty, and `run`
//  keeps a copy of the configuration `-c` names. In its interrupt mode
//  (design §11 step 3c), `run` writes the results file without its last
//  line, the end line, then waits to be stopped as SwiftMutator does: on
//  SIGTERM a `trap` appends the end line and raises the signal again
//  (`trap - TERM; kill -TERM $$`), or exits 143 as SwiftMutator's
//  fallback; each signal it hears is logged. Given `--resume <file>`
//  (design §11 step 3d), `run` appends the scenario's appended lines to
//  that file and leaves a note naming it in a run folder of its own,
//  `Nov 21, 2026 at 7:40 AM`, as SwiftMutator's resumed session does, or
//  writes the scenario's results file there instead, as a resume that
//  stopped before its first mutant writes its `stopped` line; the
//  interrupt mode doesn't resume. `run` also keeps a copy of
//  `pending.json` as it was when it started, from the mutation folder two
//  levels above the project (the harness's packages are outside git, so
//  the project is `work/<package>`). The fake `swift --version` prints the
//  recorded toolchain's version, as a `--since` run's settings check reads
//  it (design §6.1). A scenario can name the fake `swift-mutator` itself as
//  the build its results were made with, putting the script's own SHA-256
//  in place of the recorded build's, and record the SDK environment this
//  process gives it, as SwiftMutator records the one SwiftStats gives it,
//  so a `--since` run's settings check passes. A test can make the tools
//  act out another scenario between runs, keeping their paths.
//

import Foundation
@testable import SwiftStatsCore

/// A fake SwiftMutator and `swift` for the mutation collector.
struct FakeMutator {
    /// How `run` ends in its interrupt mode once SIGTERM reaches it.
    enum Interrupt: Sendable {
        /// It appends the end line and raises SIGTERM again.
        case raising
        /// It appends the end line and exits 143.
        case exiting143
    }

    /// What the fake tools do.
    struct Scenario {
        /// The results file `run` writes; none when nil.
        var results: String?
        /// What `run` prints on standard output.
        var log = ""
        /// What `run` prints on standard error.
        var errorText = ""
        /// `run`'s exit status.
        var status: Int32 = 0
        /// The signal `run` raises before exiting, when set.
        var signal: Int32?
        /// The JSON report `report` writes; none when nil.
        var report: String?
        /// `report`'s exit status.
        var reportStatus: Int32 = 0
        /// `swift build --build-tests`'s exit status.
        var buildStatus: Int32 = 0
        /// What `swift build --build-tests` prints.
        var buildOutput = ""
        /// When set, `run` writes `results` without its last line, waits
        /// for SIGTERM and ends this way after appending that line.
        var interrupt: Interrupt?
        /// The lines `run --resume <file>` appends to that file; nil when
        /// it appends none.
        var appended: String?
        /// What `swift --version` prints.
        var swiftVersion = FakeMutator.recordedToolchain
        /// Whether the results and report name the fake `swift-mutator`
        /// itself as their build, by its script's SHA-256, rather than the
        /// recorded build, and record this process's SDK environment.
        var ownIdentity = false
    }

    /// The recorded runs' toolchain, as `swift --version` printed it.
    static let recordedToolchain =
        "Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)\nTarget: arm64-apple-macosx27.2.0\n"
    /// The SHA-256 of the SwiftMutator build the recordings were made with.
    static let recordedBuild = "5138cbf1b810b127accddd8d4973bb2675195797cbae9b734bd09c0ae5a35ba8"
    /// The run folder's name the fake writes into.
    static let folder = "Nov 21, 2026 at 7:32 AM"
    /// The run folder's name a resume writes into.
    static let resumeFolder = "Nov 21, 2026 at 7:40 AM"
    /// The files a scenario writes beside the tools.
    private static let scenarioFiles = [
        "log.txt", "err.txt", "status", "report-status", "build-status", "build-output.txt", "results.jsonl",
        "report.json", "signal", "end.jsonl", "interrupt", "appended.jsonl", "version.txt"
    ]
    /// The words of a `status.txt` line: `run: exit 0`.
    static let statusWords = 3
    /// How often to look whether `run` is waiting, in microseconds.
    private static let pollInterval: useconds_t = 20_000

    /// The fake `swift-mutator`.
    private static let mutatorScript = """
        #!/bin/sh
        \(record("swift-mutator"))
        value() {
            wanted="$1"; shift
            previous=""
            for argument in "$@"; do
                if [ "$previous" = "$wanted" ]; then printf '%s' "$argument"; fi
                previous="$argument"
            done
        }
        root="$(pwd -P)"
        parent="$(dirname "$root")"
        name="$(basename "$root")"
        folder="$parent/${name}_muter_logs/\(folder)"
        expand() {
            sed -e "s|@ROOT@|$root|g" -e "s|@PARENT@|$parent|g" -e "s|@NAME@|$name|g" \\
                -e "s|@FOLDER@|\(folder)|g" "$1"
        }
        stopped() {
            echo TERM >> "$here/signals"
            kill "$sleeper" 2>/dev/null
            expand "$here/end.jsonl" >> "$folder/results.jsonl"
            if [ "$(cat "$here/interrupt")" = exit ]; then exit 143; fi
            trap - TERM
            # Delivered once the trap returns: a shell holds a signal it
            # sends itself while one of its traps runs.
            kill -TERM $$
        }
        awaitStop() {
            trap 'echo INT >> "$here/signals"' INT
            trap stopped TERM
            /bin/sleep 30 &
            sleeper=$!
            echo $$ > "$here/pid"
            : > "$here/ready"
            while kill -0 "$sleeper" 2>/dev/null; do wait "$sleeper"; done
        }
        case "$1" in
            run)
                config="$(value -c "$@")"
                if [ -n "$config" ]; then cp "$config" "$here/muter.conf.yml"; fi
                pending="$(dirname "$(dirname "$root")")/pending.json"
                rm -f "$here/pending-at-run.json"
                if [ -f "$pending" ]; then cp "$pending" "$here/pending-at-run.json"; fi
                resume="$(value --resume "$@")"
                if [ -n "$resume" ]; then
                    next="$parent/${name}_muter_logs/\(resumeFolder)"
                    mkdir -p "$next"
                    if [ -f "$here/appended.jsonl" ]; then
                        expand "$here/appended.jsonl" >> "$resume"
                        printf '%s\n' "$resume" > "$next/resumed session.txt"
                    fi
                    if [ -f "$here/results.jsonl" ]; then expand "$here/results.jsonl" > "$next/results.jsonl"; fi
                elif [ -f "$here/results.jsonl" ]; then
                    mkdir -p "$folder"
                    expand "$here/results.jsonl" > "$folder/results.jsonl"
                fi
                expand "$here/log.txt"
                cat "$here/err.txt" >&2
                if [ -f "$here/interrupt" ]; then awaitStop; fi
                if [ -f "$here/signal" ]; then kill -"$(cat "$here/signal")" $$; sleep 5; fi
                exit "$(cat "$here/status")"
                ;;
            report)
                out="$(value -o "$@")"
                if [ -f "$here/report.json" ]; then expand "$here/report.json" > "$out"; fi
                exit "$(cat "$here/report-status")"
                ;;
        esac
        exit 64
        """

    /// The fake `swift`.
    private static let swiftScript = """
        #!/bin/sh
        \(record("swift"))
        if [ "$1" = "--version" ]; then
            cat "$here/version.txt"
            exit 0
        fi
        if [ "$1" = "build" ]; then
            sed -e "s|@ROOT@|$(pwd -P)|g" "$here/build-output.txt"
            mkdir -p .build
            echo built >> .build/builds.txt
            exit "$(cat "$here/build-status")"
        fi
        exit 0
        """

    /// The tools' directory.
    let directory: URL

    /// The fake `swift-mutator`.
    var mutator: URL {
        directory.appendingPathComponent("swift-mutator")
    }

    /// The fake `swift`.
    var swift: URL {
        directory.appendingPathComponent("swift")
    }

    /// The fake `swift-mutator`'s build identity: `sha256:` and its
    /// script's SHA-256.
    var identity: String {
        "sha256:" + (ContentHash.sha256(ofFileAt: mutator) ?? "")
    }

    /// The configuration the last `run` was given, as it read it.
    var configuration: String? {
        try? String(contentsOf: directory.appendingPathComponent("muter.conf.yml"), encoding: .utf8)
    }

    /// The signals `run` heard in its interrupt mode, in order: `INT` or
    /// `TERM`.
    var signalsHeard: [String] {
        lines("signals")
    }

    /// `pending.json` as it was when the last `run` started; nil when
    /// there was none.
    var pendingAtRun: String? {
        try? String(contentsOf: directory.appendingPathComponent("pending-at-run.json"), encoding: .utf8)
    }

    /// New tools acting out `scenario`.
    static func make(_ scenario: Scenario) throws -> Self {
        let tools = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeMutator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let fake = Self(directory: tools)
        try fake.script("swift-mutator", mutatorScript)
        try fake.script("swift", swiftScript)
        try fake.act(scenario)
        return fake
    }

    /// What every fake tool records about its call, as `tool`.
    private static func record(_ tool: String) -> String {
        """
        here="$(dirname "$0")"
        for argument in "$@"; do printf '%s\\t' "$argument" >> "$here/\(tool).log"; done
        printf '\\n' >> "$here/\(tool).log"
        pwd -P >> "$here/\(tool)-cwd.log"
        echo "${NO_COLOR-unset}" >> "$here/\(tool)-env.log"
        if IFS= read -r line; then input=input; else input=empty; fi
        echo "$input" >> "$here/\(tool)-stdin.log"
        """
    }

    /// The calls of `tool` (`swift-mutator` or `swift`), each its arguments.
    func calls(of tool: String) -> [[String]] {
        lines("\(tool).log").map { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).dropLast().map(String.init)
        }
    }

    /// The lines `tool` wrote about each call: `cwd` (its real working
    /// directory), `env` (`NO_COLOR`) or `stdin` (`empty` or `input`).
    func facts(_ fact: String, of tool: String) -> [String] {
        lines("\(tool)-\(fact).log")
    }

    /// The process identifier of `run` once, in its interrupt mode, it
    /// waits to be stopped; nil when it doesn't within `timeout` seconds.
    func waitingRun(within timeout: TimeInterval) -> pid_t? {
        let ready = directory.appendingPathComponent("ready")
        let deadline = Date().addingTimeInterval(timeout)
        while FileManager.default.fileExists(atPath: ready.path) == false {
            guard Date() < deadline else {
                return nil
            }
            usleep(Self.pollInterval)
        }
        return lines("pid").first.flatMap { pid_t($0) }
    }

    /// Makes the tools act out `scenario` from their next call on.
    func act(_ scenario: Scenario) throws {
        let build = String(identity.dropFirst("sha256:".count))
        let environment = try Self.recordedEnvironment()
        let named = { (text: String?) in
            scenario.ownIdentity
                ? text?.replacingOccurrences(of: Self.recordedBuild, with: build)
                    .replacingOccurrences(of: #""environment":{}"#, with: environment)
                : text
        }
        var files = [
            "log.txt": scenario.log,
            "err.txt": scenario.errorText,
            "status": "\(scenario.status)",
            "report-status": "\(scenario.reportStatus)",
            "build-status": "\(scenario.buildStatus)",
            "build-output.txt": scenario.buildOutput,
            "version.txt": scenario.swiftVersion
        ]
        files["results.jsonl"] = named(scenario.results)
        files["report.json"] = named(scenario.report)
        files["signal"] = scenario.signal.map { "\($0)" }
        files["appended.jsonl"] = named(scenario.appended)
        if let ending = scenario.interrupt, let results = named(scenario.results) {
            var lines = results.split(separator: "\n").map(String.init)
            let end = lines.popLast() ?? ""
            files["results.jsonl"] = lines.map { $0 + "\n" }.joined()
            files["end.jsonl"] = end + "\n"
            files["interrupt"] = ending == .raising ? "raise" : "exit"
        }
        for name in Self.scenarioFiles {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        for (name, text) in files {
            try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    /// Removes the tools.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The lines of the file `name` beside the tools.
    private func lines(_ name: String) -> [String] {
        let text = (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// Writes the executable script `name` holding `body`.
    private func script(_ name: String, _ body: String) throws {
        let url = directory.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
