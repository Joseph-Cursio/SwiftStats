//
//  EarlierSnapshotTests.swift
//  SwiftStatsCoreTests
//
//  The earlier snapshot divergent clones compares with (PRD §8): which
//  stored snapshot is chosen, and how the signal is left out when none
//  qualifies or git can't say what changed.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Earlier snapshot")
struct EarlierSnapshotTests {
    /// A one-function file whose body is `value`, so each commit changes it.
    static func note(_ value: Int) -> [String: String] {
        ["Sources/Lib/Note.swift": "func note() -> Int {\n    \(value)\n}\n"]
    }

    @Test("the earlier snapshot is the latest with clone data at or before the window's start; none without clone data")
    func choosing() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        try repository.commit(Self.note(0), "Start", day: 0)
        try repository.scan(withClones: false)
        try repository.commit(Self.note(5), "Early", day: 5)
        let early = try repository.scan(withClones: false)
        let none = try repository.signal(.divergentClones, id: early)
        let chosen = try repository.commit(Self.note(10), "Chosen", day: 10)
        try repository.scan()
        let without = try repository.commit(Self.note(100), "No clone data", day: 100)
        try repository.scan(withClones: false)
        let late = try repository.commit(Self.note(150), "In the window", day: 150)
        try repository.scan()
        let current = try repository.commit(Self.note(200), "Current", day: 200)
        let id = try repository.scan()

        let workspace = try repository.workspace(withClones: true)
        let inputs = try workspace.signalInputs(for: try workspace.store.load(id: id))
        let signal = try repository.signal(.divergentClones, id: id)

        #expect(none.leftOut == DivergentClones.noEarlier)
        #expect(none.rule == DivergentClones.rule)
        #expect(none.candidates == 0)
        // The window starts on day 110: day 150 is inside it, day 100 has no clone data.
        #expect(inputs.earlier?.info.git.commit == chosen)
        #expect(inputs.earlierNote == "\(chosen.prefix(10)) of 2026-01-11")
        #expect(inputs.since == [without, late, current])
        #expect(inputs.hunks == ["Sources/Lib/Note.swift": [DiffHunk(start: 2, count: 1)]])
        #expect(inputs.gitFailure == nil)
        #expect(signal.leftOut == nil)
        #expect(signal.candidates == 0)
        #expect(signal.rule.contains("since \(chosen.prefix(10)) of 2026-01-11; 0 copies"))
    }

    @Test("a git failure leaves divergent clones out with git's reason, and the other signals in")
    func gitFailure() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let other = try HistoryRepository()
        defer { other.remove() }
        try repository.commit(Self.note(0), "Start", day: 0)
        try repository.scan()
        let current = try repository.commit(Self.note(1), "Current", day: 1)
        let id = try repository.scan()
        // A workspace on another repository, reading this one's store: the
        // snapshot's commit is unknown there.
        let store = repository.repository.root
            .appendingPathComponent(StoreLocation.directoryName)
            .appendingPathComponent(StoreLocation.fileName)
        let elsewhere = try SnapshotWorkspace(
            packageRoot: other.root,
            configurationFile: nil,
            storeOverride: store.path,
            build: SnapshotHarness.build,
            describer: HistoryRepository.DiskDescriber(),
            tools: SnapshotHarness.noTools
        )

        let inputs = try elsewhere.signalInputs(for: try elsewhere.store.load(id: id))
        let signals = try elsewhere.signals(id: id)
        let divergent = try #require(signals.first { $0.name == .divergentClones })

        let failure = try #require(inputs.gitFailure)
        #expect(failure.hasPrefix("git could not read the first-parent line of \(current.prefix(10)): "))
        #expect(inputs.earlier == nil)
        #expect(divergent.leftOut == failure)
        #expect(signals.first { $0.name == .hotspot }?.leftOut == nil)
        #expect(throws: ScanError.self) {
            try GitChanges.commits(from: String(repeating: "0", count: 40), to: current, in: repository.repository.root)
        }
        // With an earlier snapshot in hand, git's failure still wins.
        let loaded = try elsewhere.store.load(id: id)
        let compared = SignalInputs(snapshot: loaded, earlier: loaded, earlierNote: "note", gitFailure: "git failed")
        let result = SignalEngine.signals(of: compared, thresholds: SignalThresholds())
        #expect(result.first { $0.name == .divergentClones }?.leftOut == "git failed")
    }
}
