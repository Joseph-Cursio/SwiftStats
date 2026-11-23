import Foundation
@testable import SwiftStatsCore
import Testing

/// How the engine ranks what a signal scores, when it leaves a signal out,
/// and the item shape of report schema 3 and top schema 2 (M4 §5).
@Suite("Signal inputs and order")
struct SignalOrderTests {
    /// A draft about `name`'s function in `Sources/Lib/<file>`.
    private static func draft(_ name: String, file: String = "A.swift", line: Int = 1) -> SignalItem.Draft {
        SignalItem.Draft(subject: "Lib::func \(name)()", file: "Sources/Lib/\(file)", line: line)
    }

    /// A computation over `candidates` scoring `scored`.
    private static func computation(_ scored: [SignalScore], candidates: Int = 10) -> SignalComputation {
        SignalComputation(rule: "rule", candidates: candidates, scored: scored)
    }

    /// A function changed in three commits after the one adding it, in a
    /// fresh repository.
    private static func repository() throws -> HistoryRepository {
        let repository = try HistoryRepository()
        let source = { (step: Int) in
            "func busy(_ value: Int) -> Int {\n    if value > \(step) { return 1 }\n    return 0\n}\n"
        }
        try repository.write(["Sources/Lib/Busy.swift": source(0)])
        try repository.commit("Add busy", day: 0)
        for step in 1...3 {
            try repository.write(["Sources/Lib/Busy.swift": source(step)])
            try repository.commit("Change busy, \(step)", day: 200 + step)
        }
        return repository
    }

    /// The keys of the JSON object `value`.
    private static func keys(_ value: Any?) -> Set<String> {
        Set((value as? [String: Any]).map { Array($0.keys) } ?? [])
    }

    /// A clone class compared with an earlier snapshot: one copy changed
    /// since, one not.
    private static func divergentClone() -> SignalItem.Clone {
        let changed = SignalItem.CloneCopy(
            family: "Lib::func a()",
            file: "Sources/Lib/A.swift",
            line: 1,
            changes: 2,
            lastChange: "2026-10-07T00:00:00Z"
        )
        let unchanged = SignalItem.CloneCopy(
            family: "Lib::func b()",
            file: "Sources/Lib/B.swift",
            line: 1,
            changes: 0,
            lastChange: nil
        )
        let divergence = SignalItem.Divergence(
            sinceCommit: "d77ebb8",
            folded: [5],
            changed: [changed],
            unchanged: [unchanged]
        )
        return SignalItem.Clone(
            ordinal: 3,
            pass: .subtree,
            exact: true,
            mass: 40,
            lines: 6,
            copies: 2,
            churn: nil,
            divergence: divergence,
            coverage: nil
        )
    }

    @Test("a signal's own sort key decides its order, whatever the scores, and rank is the position")
    func ownSortKey() {
        // A key ordering by line, highest first: the reverse of the scores.
        let scored = [(1, 30.0), (3, 10.0), (2, 20.0)].map { line, score in
            SignalScore(
                Self.draft("f\(line)", line: line),
                score: score,
                sortKey: SignalSortKey([.number(-Double(line))])
            )
        }

        let result = SignalEngine.result(.safeToLeave, Self.computation(scored), thresholds: SignalThresholds())

        #expect(result.items.map(\.line) == [3, 2, 1])
        #expect(result.items.map(\.score) == [10, 20, 30])
        #expect(result.items.map(\.rank) == [1, 2, 3])
        #expect(result.members.count == 3)
        #expect(result.candidates == 10)
        #expect(result.rule == "rule")
    }

    @Test("the default key orders by score, highest first, then subject, file and line")
    func defaultSortKey() {
        let scored = [
            SignalScore(Self.draft("beta"), score: 5),
            SignalScore(Self.draft("alpha", file: "B.swift"), score: 5),
            SignalScore(Self.draft("alpha", file: "A.swift", line: 9), score: 5),
            SignalScore(Self.draft("alpha", file: "A.swift", line: 2), score: 5),
            SignalScore(Self.draft("zeta"), score: 7)
        ]

        let result = SignalEngine.result(.safeToLeave, Self.computation(scored), thresholds: SignalThresholds())

        #expect(result.items.map { "\($0.subject) \($0.file):\($0.line)" } == [
            "Lib::func zeta() Sources/Lib/A.swift:1",
            "Lib::func alpha() Sources/Lib/A.swift:2",
            "Lib::func alpha() Sources/Lib/A.swift:9",
            "Lib::func alpha() Sources/Lib/B.swift:1",
            "Lib::func beta() Sources/Lib/A.swift:1"
        ])
    }

    @Test("a ranked signal drops scores of zero or less and keeps ties at the cut; another lists what it scores")
    func rankedCut() {
        let scored = [("zero", 0.0), ("five", 5), ("threeA", 3), ("threeB", 3), ("minus", -1)].map { name, score in
            SignalScore(Self.draft(name), score: score)
        }
        let hotspot = { (percent: Double) in
            SignalEngine.result(
                .hotspot,
                Self.computation(scored),
                thresholds: SignalThresholds(percents: ["hotspot": percent])
            )
        }

        // 10% of 10 candidates is one member; 20% is two, and the tie at the cut makes three.
        #expect(hotspot(10).items.map(\.subject) == ["Lib::func five()", "Lib::func threeA()", "Lib::func threeB()"])
        #expect(hotspot(10).members.count == 1)
        #expect(hotspot(20).members.count == 3)
        let other = SignalEngine.result(.unstableFixes, Self.computation(scored), thresholds: SignalThresholds())
        #expect(other.items.count == 5)
        #expect(other.members.count == 5)
    }

    @Test("a signal is left out for missing history as M3 said it, for a snapshot before M4, or a collector's state")
    func leftOutReasons() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Inputs")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let files = ["Sources/Lib/Lib.swift": "func one() -> Int {\n    1\n}\n"]
        let snapshot = try SnapshotHarness.stored(files, commit: "c1", in: store)
        let reason = { (requirements: [SignalRequirement], snapshot: StoredSnapshot) in
            SignalEngine.leftOut(requirements, in: snapshot)
        }
        let history = "history was not collected: skipped, not in a git repository with commits"
        let skipped = "needs swiftinferproperties: skipped, `swift-infer` not found on PATH; "
            + "set collectors.swiftinferproperties.path"

        #expect(snapshot.reportSchemaVersion == ScanReport.currentSchemaVersion)
        #expect(reason([.history], snapshot) == history)
        #expect(reason([.collector("swiftinferproperties"), .history], snapshot) == history)
        #expect(reason([.collector("swiftinferproperties")], snapshot) == skipped)
        #expect(reason([.collector("swifteffectinference"), .m4Snapshot], snapshot) == nil)
        #expect(reason([.collector("swifteffectinference"), .collector("swiftinferproperties")], snapshot) == skipped)
        #expect(reason([.collector("nosuchcollector")], snapshot) == "the snapshot predates M4")

        let failure = "UPDATE collectorRun SET state = 'failed', reason = NULL WHERE name = 'swiftlint'"
        try SnapshotHarness.sqlite(url, failure)
        let failed = try store.load(id: snapshot.id)
        try SnapshotHarness.sqlite(url, "UPDATE snapshot SET reportSchemaVersion = 5")
        let old = try store.load(id: snapshot.id)

        #expect(reason([.collector("swiftlint")], failed) == "needs swiftlint: failed")
        #expect(old.reportSchemaVersion == 5)
        #expect(reason([.m4Snapshot], old) == "the snapshot predates M4")
        #expect(reason([.collector("swifteffectinference")], old) == "the snapshot predates M4")
        #expect(reason([.history], old) == history)
        let signals = SignalEngine.signals(of: SignalInputs(snapshot: old), thresholds: SignalThresholds())
        #expect(signals.map(\.name) == SignalName.reportOrder)
        #expect(signals.allSatisfy { $0.items.isEmpty && $0.candidates == 0 })
        // M3's signals keep history's reason; M4's, M5's and M6's say the
        // snapshot predates their milestone.
        #expect(signals.map(\.leftOut) == signals.map { signal in
            let requirements = signal.name.requirements
            let milestone = requirements.contains(.m6Snapshot) ? "M6" : requirements.contains(.m5Snapshot) ? "M5" : "M4"
            return signal.name.requirements.contains(.history) ? history : "the snapshot predates \(milestone)"
        })
    }

    @Test("report 4 and top 3 name each item's subject and carry M3's inputs in history, and no other payload")
    func itemShape() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let id = try workspace.scanWorkingTree().id
        let info = try workspace.store.info(id: id)
        let signals = try workspace.signals(id: id)
        let hotspot = try #require(signals.first { $0.name == .hotspot })

        let top = try JSONSerialization.jsonObject(
            with: try ScanReportEncoder.encode(TopReport(snapshot: info, signal: hotspot, limit: 5))
        ) as? [String: Any]
        let report = try JSONSerialization.jsonObject(with: try ScanReportEncoder.encode(
            SnapshotReport(snapshot: info, signals: signals, scan: try workspace.store.report(id: id))
        )) as? [String: Any]
        let topItems = (top?["signal"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
        let reportSignals = report?["signals"] as? [[String: Any]] ?? []
        let reportHotspot = reportSignals.first { $0["name"] as? String == "hotspot" }
        let reportItems = reportHotspot?["items"] as? [[String: Any]] ?? []

        #expect(TopReport.currentSchemaVersion == 3)
        #expect(SnapshotReport.currentSchemaVersion == 4)
        #expect(top?["schemaVersion"] as? Int == 3)
        #expect(report?["schemaVersion"] as? Int == 4)
        let item = try #require(topItems.first)
        #expect(topItems.count == 1)
        #expect(Self.keys(item) == ["rank", "subject", "file", "line", "score", "member", "history"])
        #expect(item["subject"] as? String == "Lib::func busy(_: Int) -> Int")
        #expect(Self.keys(item["history"]) == [
            "changes", "cognitive", "fixes", "allFixes", "fixScore", "reverts", "repeatedFixes", "testChanges",
            "firstSeen", "tracedBy"
        ])
        #expect(reportItems.map(Self.keys) == [Self.keys(item)])
        let history = try #require(hotspot.items.first?.history)
        #expect(history.changes == 3)
        #expect(history.cognitive == 1)
        #expect(history.tracedBy == .key)
        let decoded = try JSONDecoder().decode(
            TopReport.self,
            from: try ScanReportEncoder.encode(TopReport(snapshot: info, signal: hotspot, limit: 5))
        )
        #expect(decoded.signal == hotspot)
    }

    @Test("the M4 payloads carry every column their tables show, leaving out what wasn't collected")
    func payloadShape() throws {
        // A pure, value-shaped function whose body gave no tier, and a
        // clone class compared with an earlier snapshot.
        var draft = Self.draft("merge")
        draft.effect = SignalItem.Effect(inferred: nil, purity: .pure, source: .purity, shape: .binary)
        draft.function = SignalItem.Function(bodyLines: 4, cognitive: nil)
        draft.clone = Self.divergentClone()
        let result = SignalEngine.result(
            .safeToLeave,
            Self.computation([SignalScore(draft, score: 4)]),
            thresholds: SignalThresholds()
        )
        let item = try #require(result.items.first)

        let json = try JSONSerialization.jsonObject(with: try ScanReportEncoder.encode(item)) as? [String: Any]
        let clone = json?["clone"] as? [String: Any]
        let copies = clone?["divergence"] as? [String: Any]

        #expect(Self.keys(json) == [
            "rank", "subject", "file", "line", "score", "member", "effect", "function", "clone"
        ])
        #expect(Self.keys(json?["effect"]) == ["purity", "source", "shape"])
        #expect((json?["effect"] as? [String: Any])?["shape"] as? String == "binaryOperation")
        #expect(Self.keys(json?["function"]) == ["bodyLines"])
        #expect(Self.keys(clone) == ["ordinal", "pass", "exact", "mass", "lines", "copies", "divergence"])
        #expect(Self.keys(copies) == ["sinceCommit", "folded", "changed", "unchanged"])
        #expect(Self.keys((copies?["changed"] as? [Any])?.first) == ["family", "file", "line", "changes", "lastChange"])
        #expect(Self.keys((copies?["unchanged"] as? [Any])?.first) == ["family", "file", "line", "changes"])
        #expect(try JSONDecoder().decode(SignalItem.self, from: try ScanReportEncoder.encode(item)) == item)
    }

    @Test("the history the signals rest on heads the first history signal, once")
    func historyHeader() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let id = try workspace.scanWorkingTree().id
        let report = SnapshotReport(
            snapshot: try workspace.store.info(id: id),
            signals: try workspace.signals(id: id),
            scan: try workspace.store.report(id: id)
        )

        let lines = MarkdownReport.render(report).components(separatedBy: "\n")
        let headers = lines.indices.filter { lines[$0].hasPrefix("From the history of ") }

        #expect(headers.count == 1)
        let header = try #require(headers.first)
        #expect(lines[header - 2] == "## Signals")
        #expect(lines[header + 2] == "### Hotspots")
    }
}
