//
//  SignalHarness.swift
//  SwiftStatsCoreTests
//
//  Scans a temporary package with a fake `swift-infer`, stores the scan
//  and computes its signals, for the M4 signal tests: the signals read the
//  store's typed rows, so the tests go through the store as `report` does.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Stores scans of temporary packages and computes their signals.
enum SignalHarness {
    /// `files` as a package of `targets`, scanned with a fake indexer
    /// giving each target in `indexes` its index (none when absent), stored
    /// in a new store and read back.
    static func stored(
        _ files: [String: String],
        targets: [DescribedTarget],
        indexes: [String: String]
    ) throws -> StoredSnapshot {
        let tool = try FakeTool.makeIndexer(indexes: indexes, errors: [:], statuses: [:], delays: [:])
        defer { PropertyHarness.remove(tool) }
        return try stored(files, targets: targets, tools: PropertyHarness.locator(tool))
    }

    /// `files` as a package of `targets`, scanned finding tools with
    /// `tools`, stored in a new store and read back.
    static func stored(
        _ files: [String: String],
        targets: [DescribedTarget],
        tools: ToolLocator
    ) throws -> StoredSnapshot {
        let package = try TemporaryPackage(files, targets: targets)
        defer { package.remove() }
        let directory = try SnapshotHarness.temporaryDirectory("Signals")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let snapshot = try SnapshotHarness.scan(package, commit: "c1", build: SnapshotHarness.build, tools: tools)
        return try store.load(id: try store.save(snapshot))
    }

    /// The signal `name` computed from `snapshot`.
    static func signal(_ name: SignalName, of snapshot: StoredSnapshot) throws -> SignalResult {
        let signals = SignalEngine.signals(of: SignalInputs(snapshot: snapshot), thresholds: SignalThresholds())
        return try #require(signals.first { $0.name == name })
    }

    /// The first line of `source` holding `text` after the first holding
    /// `marker` (from the start when `marker` is empty), from 1; 0 when none does.
    static func line(of text: String, after marker: String, in source: String) -> Int {
        let lines = source.components(separatedBy: "\n")
        let start = marker.isEmpty ? 0 : (lines.firstIndex { $0.contains(marker) } ?? lines.count)
        return (lines[start...].firstIndex { $0.contains(text) } ?? -1) + 1
    }

    /// `top`'s table rows for `signal`, without its heading and summary.
    static func rows(_ signal: SignalResult) -> [String] {
        MarkdownSignals.top(signal, limit: MarkdownSignals.defaultTopLimit)
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("| ") }
    }
}
