//
//  TypeCheckCarryTests.swift
//  SwiftStatsCoreTests
//
//  The type-check roll-ups (M7, design §6.4, §9.4) once stored, on the
//  hand-made T1 snapshot: a carry takes each scope's total from its
//  stored roll-up row, which the build's rows can't give (they hold whole
//  milliseconds per record and attachment), and rebuilds the maxima and
//  the records timed from the build's rows; a snapshot holding T1 results
//  without those rows, or without one for a scope, is a damaged store;
//  and `diff` reads the four metrics as the build collector's, neutral.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The type-check roll-ups in the store, a carry and a diff.
@Suite("Type-check roll-ups stored")
struct TypeCheckCarryTests {
    /// The function-body figure `slower(_:)` gives a record.
    private static let slowerMilliseconds = 30
    /// The totals of the slower build.
    private static let slowerTotals = """
        {"module Lib": 40, "module LibTests": 0, "project production": 40, "project tests": 0}
        """

    /// The library's type-check figures in `report`.
    private static func libraryFigures(_ report: ScanReport) throws -> TypeCheckRollup {
        try #require(report.rollups.first { $0.scope == .module && $0.name == "Lib" }?.typecheck)
    }

    /// `report` with each record's function-body figure raised to
    /// `slowerMilliseconds` where it had one, everything else kept.
    private static func slower(_ report: BuildReport) -> BuildReport {
        BuildReport(
            complete: report.complete,
            records: report.records.map { timing in
                BuildRecordTiming(
                    key: timing.key,
                    milliseconds: timing.milliseconds.map { _ in slowerMilliseconds },
                    slowestExpression: timing.slowestExpression
                )
            },
            attachments: report.attachments,
            unmapped: report.unmapped,
            dropped: report.dropped,
            totals: report.totals,
            changedFiles: report.changedFiles,
            unparsedTimingLines: report.unparsedTimingLines,
            escapedLines: report.escapedLines,
            otherWarningLines: report.otherWarningLines,
            warningsDropped: report.warningsDropped,
            warningsUnmapped: report.warningsUnmapped,
            pluginWarnings: report.pluginWarnings
        )
    }

    /// `snapshot` with its build run given an identity, so `diff` can
    /// compare the build's results.
    private static func identified(_ snapshot: ScannedSnapshot) throws -> ScannedSnapshot {
        let run = try #require(snapshot.info.collectors.first { $0.name == BuildAdapter.name })
        let named = CollectorRunInfo(
            name: run.name,
            state: run.state,
            reason: run.reason,
            version: run.version,
            identity: "build:test",
            identityLabel: nil,
            options: run.options,
            durationMilliseconds: run.durationMilliseconds
        )
        return ScannedSnapshot(info: snapshot.info.with(run: named), report: snapshot.report)
    }

    @Test("""
        a carry takes each scope's total from its stored roll-up row and rebuilds the maxima and records timed from \
        the build's rows
        """)
    func carried() throws {
        let made = try TemporaryStore("TypeCheckCarry")
        defer { made.remove() }
        let snapshot = try IndexStoreSamples.snapshot(commit: "c1")
        let id = try made.store.save(snapshot)
        let held = try #require(try made.store.heldIndex(id: id))
        let plain = IndexStoreSamples.plain(snapshot)
        let carried = IndexCarry.carried(held, onto: plain).report
        let library = try Self.libraryFigures(carried)

        #expect(held.typeCheckTotals == IndexStoreSamples.typeCheckTotals)
        #expect(plain.report.rollups.allSatisfy { $0.typecheck == nil })
        #expect(carried.rollups.map(\.typecheck) == snapshot.report.rollups.map(\.typecheck))
        // The total as stored, not the 16 the record's and the file's own figures add to.
        #expect(library.milliseconds.total == 17)
        // `one()`'s 12 ms with a 3 ms expression; `two()` holds an expression only.
        #expect(library.milliseconds.max == 12 && library.slowestExpression.max == 3)
        #expect(library.functions.timed == 1)
        let saved = try made.store.save(ScannedSnapshot(info: snapshot.info, report: carried))
        #expect(try made.store.heldIndex(id: saved)?.typeCheckTotals == IndexStoreSamples.typeCheckTotals)
    }

    @Test("""
        a snapshot holding T1 results whose roll-ups have no type-check totals, a scope without one, or a fraction, \
        is a damaged store
        """)
    func damaged() throws {
        let made = try TemporaryStore("TypeCheckDamaged")
        defer { made.remove() }
        let snapshot = try IndexStoreSamples.snapshot(commit: "c1")
        let damages = [
            "DELETE FROM rollupMetric WHERE metric = 'typecheck.milliseconds.total'",
            """
            DELETE FROM rollupMetric WHERE metric = 'typecheck.milliseconds.total' AND scope = 'project' \
            AND name = 'production'
            """,
            "UPDATE rollupMetric SET value = 1.5 WHERE metric = 'typecheck.milliseconds.total' AND name = 'Lib'"
        ]

        for damage in damages {
            let id = try made.store.save(snapshot)
            #expect(try made.store.heldIndex(id: id)?.typeCheckTotals == IndexStoreSamples.typeCheckTotals)
            try SnapshotHarness.sqlite(made.url, damage)

            #expect(throws: StoreError.corruptReport("the type-check roll-ups of snapshot \(id)"), "\(damage)") {
                try made.store.heldIndex(id: id)
            }
        }
    }

    @Test("diff lists changed type-check roll-ups as the build collector's, neutral, never better or worse")
    func neutralDiff() throws {
        let made = try TemporaryStore("TypeCheckDiff")
        defer { made.remove() }
        let old = try IndexStoreSamples.snapshot(commit: "c1")
        let sample = try IndexStoreSamples.snapshot(commit: "c2")
        let status = try #require(sample.report.collectors.first { $0.name == BuildAdapter.name })
        let slower = Self.slower(try #require(sample.report.build))
        let totals = try TypeCheckTotals.given(Self.slowerTotals)
        let new = ScannedSnapshot(
            info: sample.info,
            report: sample.report.with(build: slower, totals: totals, status: status)
        )
        let diff = SnapshotDiff.diff(
            try made.store.load(id: try made.store.save(try Self.identified(old))),
            try made.store.load(id: try made.store.save(try Self.identified(new)))
        )
        let changed = diff.rollups.filter { $0.delta.metric.hasPrefix("typecheck.") }

        #expect(diff.collectors.first { $0.name == BuildAdapter.name }?.outcome == .compared)
        #expect(changed.map { "\($0.name) \($0.delta.metric) \($0.delta.before ?? -1) \($0.delta.after ?? -1)" } == [
            "Lib typecheck.milliseconds.max 12.0 30.0", "Lib typecheck.milliseconds.total 17.0 40.0",
            "production typecheck.milliseconds.max 12.0 30.0", "production typecheck.milliseconds.total 17.0 40.0"
        ])
        #expect(changed.allSatisfy { $0.collector == BuildAdapter.name })
        #expect(changed.allSatisfy { $0.delta.direction == .neutral && $0.delta.verdict == .neutral })
    }
}
