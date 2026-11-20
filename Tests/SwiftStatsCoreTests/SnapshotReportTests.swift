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

    @Test("a table cell's pipes and line breaks stay inside its row")
    func tableCells() {
        let note = "line one | a\nline two\r\nthree"
        let table = MarkdownTable(header: ["Collector", "Note"], rows: [["swiftlint", note]])

        #expect(table.lines(empty: "") == [
            "| Collector | Note |", "| --- | --- |", "| swiftlint | line one \\| a<br>line two<br>three |"
        ])
    }

    @Test("the Markdown report leads with the signals, then the collectors, the project and the modules")
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
            scan: try store.report(id: id)
        )
        let text = MarkdownReport.render(report)

        let headings = text.split(separator: "\n").filter { $0.hasPrefix("#") }.map(String.init)
        let expected = [
            "# Probe", "## Signals", "### Hotspots", "### Bug-prone", "### Unstable fixes",
            "### Tests not keeping up", "### Safe to leave", "### Untested properties", "### Tool disagreements",
            "### Missing templates", "### Unchecked laws", "## Collectors", "## Project",
            "### Findings by rule", "### Findings by kind", "## Side effects", "## Property candidates",
            "## Law checks", "## Clones", "## Modules"
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
        // The package declares no conformance the kit covers.
        #expect(text.contains("| notRun | 0 |"))
    }
}
