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
//  fallback; each signal it hears is logged.
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
    }

    /// The run folder's name the fake writes into.
    static let folder = "Nov 21, 2026 at 7:32 AM"
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
                if [ -f "$here/results.jsonl" ]; then
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

    /// The configuration the last `run` was given, as it read it.
    var configuration: String? {
        try? String(contentsOf: directory.appendingPathComponent("muter.conf.yml"), encoding: .utf8)
    }

    /// The signals `run` heard in its interrupt mode, in order: `INT` or
    /// `TERM`.
    var signalsHeard: [String] {
        lines("signals")
    }

    /// The Mutation fixture's interrupted recording in the interrupt mode:
    /// `run` waits for SIGTERM and ends as `ending` says, rather than
    /// raising the signal itself.
    static func interruptible(_ ending: Interrupt) throws -> Scenario {
        var scenario = try recorded("interrupted")
        scenario.signal = nil
        scenario.status = 0
        scenario.interrupt = ending
        return scenario
    }

    /// The scenario of the Mutation fixture's recorded case `name`.
    static func recorded(_ name: String) throws -> Scenario {
        try recorded(name, in: MutationFixture.directory)
    }

    /// The scenario of `fixture`'s recorded case `name`: its results file,
    /// report, log tail (its log folder spelled `@NAME@_muter_logs` and its
    /// run folder `@FOLDER@`) and how it ended.
    static func recorded(_ name: String, in fixture: URL) throws -> Scenario {
        let recording = MutationFixture.recorded(name, in: fixture)
        let read = { (file: String) in
            try? String(contentsOf: recording.appendingPathComponent(file), encoding: .utf8)
        }
        var scenario = Scenario()
        scenario.results = read("results.jsonl")
        scenario.report = read("report.json")
        scenario.log = (read("log-tail.txt") ?? "")
            .replacing(/@PARENT@\/[^\/\n]+_muter_logs\/[^\/\n]+\//, with: "@PARENT@/@NAME@_muter_logs/@FOLDER@/")
        let status = try String(contentsOf: recording.appendingPathComponent("status.txt"), encoding: .utf8)
        for line in status.split(separator: "\n") {
            let words = line.split(separator: " ")
            guard words.count == statusWords, let last = words.last, let number = Int32(last) else {
                continue
            }
            switch (words[0], words[1]) {
            case ("run:", "exit"):
                scenario.status = number

            case ("run:", "signal"):
                scenario.signal = number

            case ("report:", "exit"):
                scenario.reportStatus = number

            default:
                break
            }
        }
        return scenario
    }

    /// New tools acting out `scenario`.
    static func make(_ scenario: Scenario) throws -> Self {
        let tools = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeMutator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let fake = Self(directory: tools)
        var files = [
            "log.txt": scenario.log,
            "err.txt": scenario.errorText,
            "status": "\(scenario.status)",
            "report-status": "\(scenario.reportStatus)",
            "build-status": "\(scenario.buildStatus)",
            "build-output.txt": scenario.buildOutput
        ]
        files["results.jsonl"] = scenario.results
        files["report.json"] = scenario.report
        files["signal"] = scenario.signal.map { "\($0)" }
        if let ending = scenario.interrupt, let results = scenario.results {
            var lines = results.split(separator: "\n").map(String.init)
            let end = lines.popLast() ?? ""
            files["results.jsonl"] = lines.map { $0 + "\n" }.joined()
            files["end.jsonl"] = end + "\n"
            files["interrupt"] = ending == .raising ? "raise" : "exit"
        }
        for (name, text) in files {
            try text.write(to: tools.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try fake.script("swift-mutator", mutatorScript)
        try fake.script("swift", swiftScript)
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
