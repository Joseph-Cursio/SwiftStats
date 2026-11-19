import Foundation
@testable import SwiftStatsCore
import Testing

/// Derived signals and their configuration (PRD §8, §10.1), the stored
/// history they read, and `top`.
@Suite("Signals")
struct SignalTests {
    /// A function with cognitive complexity `branches` (one `if` each).
    private static func branchy(_ name: String, branches: Int, tweak: Int = 0) -> String {
        let ifs = (0..<branches).map { "    if value > \($0) { total += \($0 + tweak) }" }.joined(separator: "\n")
        return "func \(name)(_ value: Int) -> Int {\n    var total = 0\n\(ifs)\n    return total\n}\n"
    }

    /// A repository where `busy` changes three times, `calm` never changes
    /// after day 0, and a generated file changes as often as `busy`.
    private static func repository() throws -> HistoryRepository {
        let repository = try HistoryRepository()
        try repository.write([
            "Sources/Lib/Busy.swift": branchy("busy", branches: 3),
            "Sources/Lib/Calm.swift": branchy("calm", branches: 5),
            "Sources/Lib/Generated/Made.swift": branchy("made", branches: 9),
            "Tests/LibTests/BusyTests.swift": "func testBusy() {}\n"
        ])
        try repository.commit("Add the code", day: 0)
        for step in 1...3 {
            try repository.write([
                "Sources/Lib/Busy.swift": branchy("busy", branches: 3, tweak: step),
                "Sources/Lib/Generated/Made.swift": branchy("made", branches: 9, tweak: step)
            ])
            try repository.commit(step == 2 ? "Fix busy" : "Tweak busy, \(step)", day: 200 + step)
        }
        return repository
    }

    @Test("history and signals keys are parsed and checked")
    func configuration() throws {
        let text = """
            history:
              window: 30d
              fix_patterns: ["^stop\\\\b"]
              repeat_window: 7d
              bulk_files: 12
              ignore_revs: [abcdef1234]
              coupling:
                min_support: 4
            signals:
              hotspot:
                threshold: 5
            """
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")

        #expect(configuration.history.windowDays == 30)
        #expect(configuration.history.fixPatterns == ["^stop\\b"])
        #expect(configuration.history.fixExcludePatterns == HistoryOptions.defaultFixExcludePatterns)
        #expect(configuration.history.repeatWindowDays == 7)
        #expect(configuration.history.bulkFiles == 12)
        #expect(configuration.history.ignoreRevs == ["abcdef1234"])
        #expect(configuration.history.couplingMinSupport == 4)
        #expect(configuration.signals.percent(for: "hotspot") == 5)
        #expect(configuration.signals.percent(for: "bug-prone") == SignalThresholds.defaultPercent)
        for invalid in [
            "history:\n  window: 90\n", "history:\n  windw: 90d\n", "history:\n  fix_patterns: [\"(\"]\n",
            "history:\n  coupling:\n    min_support: 1\n", "history:\n  ignore_revs: [zz]\n", "history: 3\n",
            "signals:\n  safe-to-leave:\n    threshold: 5\n", "signals:\n  hotspot:\n    threshold: 0\n",
            "signals:\n  hotspot:\n    cut: 5\n"
        ] {
            #expect(throws: ScanError.self, "\(invalid)") {
                try SwiftStatsConfiguration.parse(invalid, path: "c.yml")
            }
        }
    }

    @Test("signals rank production families with history; generated and test code stay out")
    func signals() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let id = try workspace.scanWorkingTree().id

        let signals = try workspace.signals(id: id)
        let byName = Dictionary(uniqueKeysWithValues: signals.map { ($0.name, $0) })
        let hotspot = try #require(byName[.hotspot])

        #expect(signals.map(\.name) == SignalName.reportOrder)
        #expect(hotspot.items.map(\.family) == ["Lib::func busy(_: Int) -> Int"])
        #expect(hotspot.items.first?.score == 9)
        #expect(hotspot.items.first?.member == true)
        #expect(hotspot.candidates == 2)
        #expect(byName[.bugProne]?.members.map(\.family) == ["Lib::func busy(_: Int) -> Int"])
        #expect(byName[.safeToLeave]?.members.map(\.family) == ["Lib::func calm(_: Int) -> Int"])
        #expect(byName[.testsNotKeepingUp]?.members.map(\.family) == ["Lib::func busy(_: Int) -> Int"])
        #expect(byName[.unstableFixes]?.members.isEmpty == true)
    }

    @Test("a ranked signal keeps the top share of candidates by nearest rank, with ties at the cut")
    func membership() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let names = ["alpha", "beta", "gamma", "delta"]
        let sources = names.map { name in ("Sources/Lib/\(name).swift", Self.branchy(name, branches: 2)) }
        try repository.write(Dictionary(uniqueKeysWithValues: sources))
        try repository.commit("Add", day: 0)
        try repository.write([
            "Sources/Lib/alpha.swift": Self.branchy("alpha", branches: 2, tweak: 1),
            "Sources/Lib/beta.swift": Self.branchy("beta", branches: 2, tweak: 1)
        ])
        try repository.commit("Change two", day: 1)
        let workspace = try repository.workspace()
        let id = try workspace.scanWorkingTree().id
        let stored = try workspace.store.load(id: id)

        let hotspot = { (percent: Double) in
            SignalEngine.signals(of: stored, thresholds: SignalThresholds(percents: ["hotspot": percent]))
                .first { $0.name == .hotspot }
        }

        // Every family changed in the first commit; alpha and beta again: scores 4, 4, 2, 2.
        #expect(hotspot(10)?.items.count == 4)
        #expect(hotspot(10)?.members.count == 2)
        #expect(hotspot(50)?.members.count == 2)
        #expect(hotspot(51)?.members.count == 4)
    }

    @Test("history is stored and read back, and a snapshot without it leaves the signals out with the reason")
    func storedHistory() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let (snapshot, id) = try workspace.scanWorkingTree()
        let stored = try workspace.store.load(id: id)

        #expect(stored.history?.commitHash == snapshot.report.history?.commit)
        #expect(stored.familyHistory.count == snapshot.report.history?.families.count)
        #expect(stored.familyHistory.first { $0.family.contains("made") }?.generated == true)

        let skipped = try workspace.scanWorkingTree(history: .skipped("--no-history")).id
        let signals = try workspace.signals(id: skipped)
        #expect(signals.allSatisfy { $0.leftOut == "history was not collected: skipped, --no-history" })
    }

    @Test("report and top give byte-identical JSON each time, and top marks members")
    func topReport() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let id = try workspace.scanWorkingTree().id

        let render = {
            let fresh = try repository.workspace()
            let info = try fresh.store.info(id: id)
            let signals = try fresh.signals(id: id)
            let report = SnapshotReport(snapshot: info, signals: signals, scan: try fresh.store.report(id: id))
            let hotspot = try #require(signals.first { $0.name == .hotspot })
            return (
                try ScanReportEncoder.encode(report),
                try ScanReportEncoder.encode(TopReport(snapshot: info, signal: hotspot, limit: 5)),
                MarkdownSignals.top(hotspot, limit: 5)
            )
        }
        let first = try render()
        let second = try render()

        #expect(first.0 == second.0 && first.1 == second.1 && first.2 == second.2)
        let busyRow = "| 1 | `func busy(_: Int) -> Int` (Sources/Lib/Busy.swift:1) | 9 | 3 | 3 | key | yes |"
        #expect(first.2.contains(busyRow))
        let markdown = MarkdownReport.render(try JSONDecoder().decode(SnapshotReport.self, from: first.0))
        #expect(markdown.contains("## History"))
        #expect(markdown.contains("### Fix commits"))
    }

    @Test("history compares only when SwiftStats' own build does")
    func comparability() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let old = try workspace.store.load(id: try workspace.scanWorkingTree().id)
        let other = try repository.workspace(build: SwiftStatsBuild(identity: "inputs:other", label: nil))
        let new = try other.store.load(id: try other.scanWorkingTree().id)

        let outcomes = Dictionary(uniqueKeysWithValues: Comparability.compare(old.info, new.info).map { ($0.name, $0) })

        #expect(outcomes["history"]?.outcome == .notComparable)
        #expect(outcomes["history"]?.reason == "SwiftStats' build differs, and its own code reads the history")
        #expect(Comparability.compare(old.info, old.info).first { $0.name == "history" }?.outcome == .compared)
    }
}
