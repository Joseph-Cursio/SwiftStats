import Foundation
@testable import SwiftStatsCore
import Testing

/// `report` (PRD §10; M2 done-when 4).
@Suite("Snapshot report")
struct SnapshotReportTests {
    @Test("re-running report on a stored snapshot gives byte-identical JSON and Markdown (done-when 4)")
    func byteIdentical() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Report")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let files = ["Sources/Lib/Lib.swift": "public func one() -> Int {\n    1\n}\n"]
        let id = try SnapshotHarness.stored(files, commit: "c1", in: SnapshotStore(at: url)).id

        let render = {
            // A fresh connection each time, as separate runs would have.
            let store = try SnapshotStore(at: url)
            let report = SnapshotReport(
                snapshot: try store.info(id: id),
                signals: SignalEngine.signals(of: SignalInputs(snapshot: try store.load(id: id)), thresholds: .init()),
                thresholds: SignalThresholds(),
                scan: try store.report(id: id)
            )
            return (try ScanReportEncoder.encode(report), MarkdownReport.render(report))
        }
        let first = try render()
        let second = try render()

        #expect(first.0 == second.0)
        #expect(first.1 == second.1)
        let decoded = try JSONDecoder().decode(SnapshotReport.self, from: first.0)
        #expect(decoded.schemaVersion == SnapshotReport.currentSchemaVersion)
        #expect(decoded.scan.schemaVersion == ScanReport.currentSchemaVersion)
        #expect(decoded.snapshot.date == "2027-01-15T08:00:00Z")
    }

    @Test("""
        report 5 lists the thresholds its signals used: every ranked signal's percent and every mutation and \
        hidden-coupling limit in effect, configured or default, genuinely under-tested's ratio only when set
        """)
    func thresholds() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Report")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let files = ["Sources/Lib/Lib.swift": "public func one() -> Int {\n    1\n}\n"]
        let id = try SnapshotHarness.stored(files, commit: "c1", in: store).id
        let encoded = { (thresholds: SignalThresholds) in
            let report = SnapshotReport(
                snapshot: try store.info(id: id),
                signals: SignalEngine.signals(
                    of: SignalInputs(snapshot: try store.load(id: id)),
                    thresholds: thresholds
                ),
                thresholds: thresholds,
                scan: try store.report(id: id)
            )
            let object = try JSONSerialization.jsonObject(with: try ScanReportEncoder.encode(report))
            return (object as? [String: Any])?["thresholds"] as? [String: [String: Any]]
        }
        let configured = SignalThresholds(
            percents: ["hotspot": 5],
            limits: ["weak-tests": ["score": 40], "genuinely-under-tested": ["ratio": 0.25]]
        )

        let defaults = try #require(try encoded(SignalThresholds()))
        let set = try #require(try encoded(configured))

        #expect(defaults["percents"] as? [String: Double] == ["bug-prone": 10, "clone-hotspot": 10, "hotspot": 10])
        #expect(defaults["limits"] as? [String: [String: Double]] == [
            "weak-tests": ["coverage": 80, "score": 50, "mutants": 3],
            "genuinely-under-tested": ["coverage": 20, "score": 20, "mutants": 3],
            "uneven-clone-mutation": ["high": 80, "low": 20, "mutants": 2],
            "hidden-coupling": ["support": 3, "confidence": 50]
        ])
        #expect(set["percents"] as? [String: Double] == ["bug-prone": 10, "clone-hotspot": 10, "hotspot": 5])
        let limits = set["limits"] as? [String: [String: Double]]
        #expect(limits?["weak-tests"] == ["coverage": 80, "score": 40, "mutants": 3])
        #expect(limits?["genuinely-under-tested"] == ["coverage": 20, "score": 20, "mutants": 3, "ratio": 0.25])
    }

    @Test("a table cell's pipes and line breaks stay inside its row")
    func tableCells() {
        let note = "line one | a\nline two\r\nthree"
        let table = MarkdownTable(header: ["Collector", "Note"], rows: [["swiftlint", note]])

        #expect(table.lines(empty: "") == [
            "| Collector | Note |", "| --- | --- |", "| swiftlint | line one \\| a<br>line two<br>three |"
        ])
    }

    @Test("""
        the Markdown report leads with the signals, then the collectors, coverage, mutation, the project and the \
        modules
        """)
    func markdownOrder() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Report")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let files = [
            "Sources/Lib/Lib.swift": """
            func check(_ value: Int?) -> Int {
                precondition(value != nil)
                return 1
            }
            """
        ]
        let id = try SnapshotHarness.stored(files, commit: "c1", in: store).id

        let report = SnapshotReport(
            snapshot: try store.info(id: id),
            signals: SignalEngine.signals(of: SignalInputs(snapshot: try store.load(id: id)), thresholds: .init()),
            thresholds: SignalThresholds(),
            scan: try store.report(id: id)
        )
        let text = MarkdownReport.render(report)

        let headings = text.split(separator: "\n").filter { $0.hasPrefix("#") }.map(String.init)
        let expected = [
            "# Probe", "## Signals", "### Hotspots", "### Bug-prone", "### Unstable fixes",
            "### Tests not keeping up", "### Safe to leave", "### Untested properties", "### Tool disagreements",
            "### Missing templates", "### Unchecked laws", "### Divergent clones", "### Clone hotspots",
            "### Risky + untested", "### Uneven clone testing", "### Weak tests", "### Genuinely under-tested",
            "### Best property-test targets", "### Uneven clone testing (mutation)", "### Hidden coupling",
            "### Dead but tested", "### Test-only production code", "## Collectors", "## Coverage",
            "## Mutation", "## Project", "### Findings by rule", "### Findings by kind", "## Side effects",
            "## Property candidates", "## Law checks", "## Clones", "## Modules"
        ]
        #expect(headings == expected)
        #expect(text.contains("Left out: history was not collected: skipped, not in a git repository with commits."))
        // One `precondition` in four stripped lines: 250 per 1k.
        #expect(text.contains("| production | swiftstats | precondition | 1 | 250.0 |"))
        // `check` traps, so purity is refuted and no tier resolves.
        #expect(text.contains("| refuted | 1 |"))
        #expect(text.contains("| pure | 0 |"))
        #expect(text.contains(
            "Not collected: skipped, `swift-infer` not found on PATH; set collectors.swiftinferproperties.path."
        ))
        #expect(text.contains(
            "Not collected: skipped, `swift-clone-detector` not found on PATH; set collectors.swiftclonedetector.path."
        ))
        #expect(text.contains("## Coverage\n\nNot collected: skipped, not requested; scan --coverage runs it.\n"))
        #expect(text.contains("## Mutation\n\nNot collected: skipped, not requested; scan --mutation runs it.\n"))
        #expect(text.contains("### Risky + untested\n\nLeft out: needs coverage: skipped, not requested; "
            + "scan --coverage runs it."))
        // The package declares no conformance the kit covers.
        #expect(text.contains("| notRun | 0 |"))
    }
}
