//
//  FakePeriphery.swift
//  SwiftStatsCoreTests
//
//  An `outskirts` of a shell script standing in for the `periphery`
//  collector's tool (M7, design §13 step 6a), so its tests never run
//  outskirts. `version` prints the scenario's version and exits with its
//  version status. `scan` is the `production` run when its arguments hold
//  `--exclude-tests`, else the `roots` run; it prints the scenario's JSON
//  for that run, `@ROOT@` the working directory (`pwd -P`) and `@DEP@` an
//  IndexDep beside it, as in the Index fixture's recordings, writes the
//  run's error text, restored alike, to standard error, then sends itself
//  the run's signal when the scenario gives one, else exits with the run's
//  status (0 by default). Each call is logged in order (`version`, `roots`,
//  `production`), and each run keeps its arguments, one a line, its
//  working directory and whether standard input is `/dev/null` (by its
//  device), beside the script.
//

import Foundation
@testable import SwiftStatsCore

/// A fake outskirts.
struct FakePeriphery {
    /// What the fake does.
    struct Scenario {
        /// What `version` prints.
        var version = "3.28.0"
        /// `version`'s exit status.
        var versionStatus: Int32 = 0
        /// Each run's JSON, placeholders unrestored.
        var outputs: [PeripheryCommand.Run: String]
        /// Each run's standard error.
        var errors: [PeripheryCommand.Run: String] = [:]
        /// Each run's exit status; 0 when absent.
        var statuses: [PeripheryCommand.Run: Int32] = [:]
        /// The signal each run sends itself once it has written its
        /// output; none when absent.
        var signals: [PeripheryCommand.Run: Int32] = [:]
    }

    /// The warning outskirts prints on every run over an index store.
    static let xcodeWarning = "warning: When using the '--index-store-path' option please ensure that Xcode is "
        + "not running. False-positives can occur if Xcode writes to the index store while outskirts is running."

    /// The script.
    let tool: URL

    /// The fake's folder.
    var directory: URL {
        tool.deletingLastPathComponent()
    }

    /// The calls made, in order: `version`, `roots` or `production`.
    var calls: [String] {
        lines("calls.log")
    }

    /// The `.swiftstats.yml` lines naming the fake as
    /// `collectors.periphery.path`, indented as under `collectors:`.
    var configuration: String {
        "  periphery:\n    path: \(tool.path)\n"
    }

    /// The scenario of the Index fixture's recorded runs, each printing
    /// outskirts' routine warning.
    static func recorded() throws -> Scenario {
        Scenario(
            outputs: [
                .roots: try IndexFixture.text("outskirts-roots.json"),
                .production: try IndexFixture.text("outskirts-production.json")
            ],
            errors: [.roots: xcodeWarning + "\n", .production: xcodeWarning + "\n"]
        )
    }

    /// A new fake acting out `scenario`.
    static func make(_ scenario: Scenario) throws -> Self {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakePeriphery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files = ["version": scenario.version + "\n", "version-status": "\(scenario.versionStatus)"]
        let perRun = [
            ("out", scenario.outputs), ("err", scenario.errors),
            ("status", scenario.statuses.mapValues { "\($0)" }), ("signal", scenario.signals.mapValues { "\($0)" })
        ]
        for (prefix, texts) in perRun {
            for (run, text) in texts {
                files["\(prefix)-\(run.rawValue)"] = text
            }
        }
        for (name, text) in files {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let script = """
            #!/bin/sh
            here="$(dirname "$0")"
            if [ "$1" = version ]; then
                echo version >> "$here/calls.log"
                cat "$here/version"
                exit "$(cat "$here/version-status")"
            fi
            run=roots
            for argument in "$@"; do
                if [ "$argument" = --exclude-tests ]; then run=production; fi
            done
            echo "$run" >> "$here/calls.log"
            printf '%s\\n' "$@" > "$here/arguments-$run.txt"
            pwd -P > "$here/cwd-$run.txt"
            if [ "$(/usr/bin/stat -L -f '%Hr,%Lr' /dev/stdin 2>/dev/null)" = "$(/usr/bin/stat -f '%Hr,%Lr' /dev/null)" ]
            then echo null; else echo inherited; fi > "$here/stdin-$run.txt"
            root="$(pwd -P)"
            restored() {
                if [ -f "$1" ]; then sed "s|@ROOT@|$root|g; s|@DEP@|$(dirname "$root")/IndexDep|g" "$1"; fi
            }
            restored "$here/out-$run"
            restored "$here/err-$run" >&2
            if [ -f "$here/signal-$run" ]; then kill -"$(cat "$here/signal-$run")" $$; fi
            if [ -f "$here/status-$run" ]; then exit "$(cat "$here/status-$run")"; fi
            exit 0

            """
        let executable = folder.appendingPathComponent("outskirts")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return Self(tool: executable)
    }

    /// The arguments `run` was made with, one an element; empty when it
    /// wasn't made.
    func arguments(of run: PeripheryCommand.Run) -> [String] {
        lines("arguments-\(run.rawValue).txt")
    }

    /// The working directory `run` was made in.
    func directory(of run: PeripheryCommand.Run) -> String? {
        lines("cwd-\(run.rawValue).txt").first
    }

    /// `null` when `run`'s standard input was `/dev/null`, else
    /// `inherited`.
    func input(of run: PeripheryCommand.Run) -> String? {
        lines("stdin-\(run.rawValue).txt").first
    }

    /// Removes the fake.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The lines of the file `name` beside the script.
    private func lines(_ name: String) -> [String] {
        let text = (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    }
}
