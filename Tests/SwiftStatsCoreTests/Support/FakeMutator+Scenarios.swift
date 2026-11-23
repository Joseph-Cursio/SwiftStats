//
//  FakeMutator+Scenarios.swift
//  SwiftStatsCoreTests
//
//  The scenarios a `FakeMutator` acts out, made from SwiftMutator's
//  recorded runs (`Scripts/record-mutation-fixture.sh`): a recorded case
//  as it was, the interrupted run waiting to be stopped, and its resume;
//  and the SDK environment a scenario that names the fake itself as its
//  build records.
//

import Foundation
@testable import SwiftStatsCore

extension FakeMutator {
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

    /// The Mutation fixture's resumed recording as a resume acts it out:
    /// `run --resume` appends the lines the resume added to the
    /// interrupted run's file, prints the resume's log and exits as it did.
    static func resuming() throws -> Scenario {
        var scenario = try recorded("resumed")
        let earlier = (try recorded("interrupted").results ?? "").split(separator: "\n").count
        let lines = (scenario.results ?? "").split(separator: "\n", omittingEmptySubsequences: false)
        scenario.appended = lines.dropFirst(earlier).joined(separator: "\n")
        scenario.results = nil
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

    /// This process's SDK environment as a results header records it:
    /// `"environment":{…}`.
    static func recordedEnvironment() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(MutationBase.sdkEnvironment(of: ProcessInfo.processInfo.environment))
        return #""environment":"# + (String(bytes: json, encoding: .utf8) ?? "{}")
    }
}
