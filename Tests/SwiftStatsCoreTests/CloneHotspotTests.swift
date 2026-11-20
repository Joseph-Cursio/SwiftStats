//
//  CloneHotspotTests.swift
//  SwiftStatsCoreTests
//
//  Clone hotspot (PRD §8) on a git fixture: classes ranked by the distinct
//  non-sweep commits in the window that changed their copies' families.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Clone hotspot")
struct CloneHotspotTests {
    /// The file holding the copies.
    static let file = "Sources/Lib/Copies.swift"
    /// The five-line functions, in file order, each at line 1 + 6 × its position.
    static let names = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa"]

    /// The classes: pairs of whole functions, a pair of fragments covering
    /// four of their functions' five stripped lines, and the hosts' loops.
    static var classes: [FakeClone] {
        let pairs = [(0, 1), (2, 3), (4, 5), (6, 7)].map { first, second in
            FakeClone(run: "default", mass: 30, spans: [(file, function(first)), (file, function(second))])
        }
        let iota = function(8)
        let kappa = function(9)
        let near = FakeClone(
            run: "default",
            mass: 25,
            spans: [(file, iota.lowerBound...(iota.upperBound - 1)), (file, kappa.lowerBound...(kappa.upperBound - 1))]
        )
        let loops = FakeClone(run: "default", mass: 20, spans: [(file, 63...64), (file, 73...74)])
        return pairs + [near, loops]
    }

    /// The copies, each function adding its tweak, followed by two hosts
    /// sharing a two-line loop (lines 63–64 and 73–74).
    static func source(tweaks: [String: Int]) -> String {
        let functions = names.map { name in
            """
            func \(name)(_ value: Int) -> Int {
                let doubled = value * 2
                let shifted = doubled + \(tweaks[name] ?? 1)
                return shifted
            }

            """
        }
        let hosts = ["host", "guest"].map { name in
            """
            func \(name)(_ values: [Int]) -> Int {
                var total = 0
                for value in values {
                    total += value
                }
                let average = total / max(values.count, 1)
                let spread = values.max() ?? 0
                return average + spread
            }

            """
        }
        return (functions + hosts).joined(separator: "\n")
    }

    /// The lines of the function at `position` in `names`.
    static func function(_ position: Int) -> ClosedRange<Int> {
        let start = 1 + 6 * position
        return start...(start + 4)
    }

    /// A repository whose functions changed as the tests expect: every one
    /// added on day 0, alpha, beta, eta and theta in one commit on day 1,
    /// gamma on day 2 and delta on day 3; with the clone data of its scan.
    static func scanned() throws -> (repository: CloneRepository, id: Int64) {
        let repository = try CloneRepository()
        var tweaks: [String: Int] = [:]
        try repository.commit([file: source(tweaks: tweaks)], "Add copies", day: 0)
        for name in ["alpha", "beta", "eta", "theta"] {
            tweaks[name] = 2
        }
        try repository.commit([file: source(tweaks: tweaks)], "Change four together", day: 1)
        tweaks["gamma"] = 3
        try repository.commit([file: source(tweaks: tweaks)], "Change gamma", day: 2)
        tweaks["delta"] = 3
        try repository.commit([file: source(tweaks: tweaks)], "Change delta", day: 3)
        try repository.report(classes)
        return (repository, try repository.scan())
    }

    @Test("a class scores its distinct commits in the window, so a commit changing every copy counts once")
    func synchronisedCommits() throws {
        let (repository, id) = try Self.scanned()
        defer { repository.remove() }

        let signal = try repository.signal(.cloneHotspot, id: id)

        #expect(signal.leftOut == nil)
        #expect(signal.items.map(\.subject) == [
            "Lib::func gamma(_: Int) -> Int", "Lib::func alpha(_: Int) -> Int", "Lib::func eta(_: Int) -> Int",
            "Lib::func epsilon(_: Int) -> Int", "Lib::func iota(_: Int) -> Int"
        ])
        // Alpha and beta changed twice each, both times together.
        #expect(signal.items.map(\.score) == [3, 2, 2, 1, 1])
        #expect(signal.items.map { $0.clone?.churn } == [3, 2, 2, 1, 1])
        #expect(signal.items.first?.clone?.copies == 2)
        #expect(signal.items.first?.clone?.lines == 10)
        #expect(signal.items.first?.clone?.divergence == nil)
        // 10% of five classes is one member.
        #expect(signal.members.map(\.subject) == ["Lib::func gamma(_: Int) -> Int"])
        #expect(SignalHarness.rows(signal).dropFirst(2).first
            == "| 1 | `func gamma(_: Int) -> Int` (Sources/Lib/Copies.swift:13) | 3 | renamed | 2 | 30 | 3 | yes |")
    }

    @Test("a class of fragments under 80% of their functions is left out and counted")
    func fragmentClasses() throws {
        let (repository, id) = try Self.scanned()
        defer { repository.remove() }

        let signal = try repository.signal(.cloneHotspot, id: id)

        #expect(signal.candidates == 5)
        #expect(signal.items.contains { $0.subject.contains("host") } == false)
        #expect(signal.items.contains { $0.subject == "Lib::func iota(_: Int) -> Int" })
        #expect(signal.rule == "top 10% of 5 classes by distinct non-sweep commits in the window changing their "
            + "copies; 1 classes with a copy covering under 80% of its function are left out")
    }

    @Test("ties at the cut are kept, and the threshold is read from the configuration")
    func tiesKept() throws {
        let (repository, id) = try Self.scanned()
        defer { repository.remove() }
        let workspace = try repository.workspace(withClones: true)
        let inputs = try workspace.signalInputs(for: try workspace.store.load(id: id))
        let members = { (percent: Double) in
            SignalEngine.signals(of: inputs, thresholds: SignalThresholds(percents: ["clone-hotspot": percent]))
                .first { $0.name == .cloneHotspot }?
                .members
                .count
        }

        // 40% of five is two, and the tie at the cut makes three.
        #expect(members(40) == 3)
        #expect(members(20) == 1)
        let configuration = try SwiftStatsConfiguration.parse(
            "signals:\n  clone-hotspot:\n    threshold: 40\n",
            path: "c.yml"
        )
        #expect(configuration.signals.percent(for: "clone-hotspot") == 40)
        for invalid in ["threshold: 0", "threshold: 101", "cut: 5"] {
            #expect(throws: ScanError.self, "\(invalid)") {
                try SwiftStatsConfiguration.parse("signals:\n  clone-hotspot:\n    \(invalid)\n", path: "c.yml")
            }
        }
    }

    @Test("clone hotspot needs clone data and history")
    func leftOut() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        try repository.commit([Self.file: Self.source(tweaks: [:])], "Add copies", day: 0)
        let withoutClones = try repository.scan(withClones: false)
        // A later commit, since a second scan of one commit replaces the first.
        try repository.commit([Self.file: Self.source(tweaks: ["alpha": 2])], "Change alpha", day: 1)
        let withoutHistory = try repository.workspace(withClones: true)
            .scanWorkingTree(history: .skipped("--no-history"))
            .id

        #expect(try repository.signal(.cloneHotspot, id: withoutClones).leftOut
            == "needs swiftclonedetector: skipped, `swift-clone-detector` not found on PATH; "
            + "set collectors.swiftclonedetector.path")
        #expect(try repository.signal(.cloneHotspot, id: withoutHistory).leftOut
            == "history was not collected: skipped, --no-history")
        #expect(try repository.signal(.divergentClones, id: withoutHistory).leftOut
            == "history was not collected: skipped, --no-history")
    }

    @Test("a copy that is a whole nested function is measured against its host, whose commits it would score")
    func nestedFunctions() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let hosts = ["outer", "other"].map { name in
            """
            func \(name)(_ values: [Int]) -> Int {
                func helper(_ value: Int) -> Int {
                    let doubled = value * 2
                    return doubled + 1
                }
                let mapped = values.map(helper)
                let total = mapped.reduce(0, +)
                return total - values.count
            }

            """
        }
        try repository.commit([Self.file: hosts.joined(separator: "\n")], "Add hosts", day: 0)
        try repository.report([FakeClone(run: "default", mass: 25, spans: [(Self.file, 2...5), (Self.file, 12...15)])])

        let signal = try repository.signal(.cloneHotspot, id: try repository.scan())

        #expect(signal.candidates == 0)
        #expect(signal.items.isEmpty)
        #expect(signal.rule.hasSuffix("; 1 classes with a copy covering under 80% of its function are left out"))
    }
}
