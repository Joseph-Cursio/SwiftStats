//
//  IndexReportHarness.swift
//  SwiftStatsCoreTests
//
//  M7's report sections on a scanned snapshot (design §10.1, §13 step
//  10): the snapshot stored in a temporary store and read back as
//  `report` reads it, its signals computed with the default thresholds,
//  rendered as Markdown and JSON, and a section's lines cut out of the
//  Markdown by its heading.
//

import Foundation
@testable import SwiftStatsCore

/// Reports of scanned snapshots, as `report` makes them.
enum IndexReportHarness {
    /// A report of a snapshot and the store holding it.
    struct Made {
        /// The report as `report` makes it.
        let report: SnapshotReport
        /// The store holding the snapshot, to remove once checked.
        let store: TemporaryStore
        /// The snapshot's id in it.
        let id: Int64
    }

    /// `snapshot` stored in a new temporary store and reported as
    /// `report` reports it; the caller removes the store.
    static func made(_ snapshot: ScannedSnapshot) throws -> Made {
        let store = try TemporaryStore("IndexReport")
        let id = try store.store.save(snapshot)
        return Made(report: try report(id: id, in: store.store), store: store, id: id)
    }

    /// Snapshot `id` of `store` as `report` reports it, with the default
    /// thresholds.
    static func report(id: Int64, in store: SnapshotStore) throws -> SnapshotReport {
        SnapshotReport(
            snapshot: try store.info(id: id),
            signals: SignalEngine.signals(of: SignalInputs(snapshot: try store.load(id: id)), thresholds: .init()),
            thresholds: SignalThresholds(),
            scan: try store.report(id: id)
        )
    }

    /// The Markdown of `snapshot`'s report.
    static func markdown(_ snapshot: ScannedSnapshot) throws -> String {
        let made = try made(snapshot)
        defer { made.store.remove() }
        return MarkdownReport.render(made.report)
    }

    /// The lines of `text`'s section headed `## heading`, up to the next
    /// section's heading, without the heading and the blank lines around
    /// it.
    static func section(_ heading: String, of text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "## \(heading)") else {
            return []
        }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## ") } ?? rest.endIndex
        var body = Array(rest[..<end])
        while body.first?.isEmpty == true {
            body.removeFirst()
        }
        while body.last?.isEmpty == true {
            body.removeLast()
        }
        return body
    }

    /// The lines of `section` from the one equal to `start` up to, not
    /// including, the first that begins with `end` after it; empty when
    /// `start` isn't there.
    static func part(_ section: [String], from start: String, to end: String) -> [String] {
        guard let first = section.firstIndex(of: start) else {
            return []
        }
        let rest = section[first...]
        let last = rest.dropFirst().firstIndex { $0.hasPrefix(end) } ?? rest.endIndex
        return Array(rest[..<last])
    }
}
