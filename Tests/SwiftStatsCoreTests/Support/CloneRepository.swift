//
//  CloneRepository.swift
//  SwiftStatsCoreTests
//
//  A git repository with fixed commit dates whose scans run a fake
//  SwiftCloneDetector reporting the classes a test sets, so the clone
//  signals can be computed from real history and real diffs: scan a
//  commit with clone data, change the code, commit, and scan again.
//

import Foundation
@testable import SwiftStatsCore

/// A repository whose scans report the clone classes a test sets.
struct CloneRepository {
    /// The detector's runs, as the fake tool names them.
    private static let runs = ["default", "--type3", "--sequence", "--type1"]
    /// The column a fake copy ends before: past the end of any fixture line.
    private static let endColumn = 200
    /// The similarity of a near-miss class.
    private static let similarity = 0.9

    /// The repository.
    let repository: HistoryRepository
    /// The fake SwiftCloneDetector.
    let tool: URL

    /// A new repository whose fake detector reports no classes.
    init() throws {
        repository = try HistoryRepository()
        tool = try FakeTool.makeCloneDetector(outputs: [:], errors: [:], statuses: [:])
        try report([])
    }

    /// The JSON the detector writes for `clones` on the run `run`.
    static func json(_ clones: [FakeClone], run: String) throws -> String {
        let classes = clones.enumerated().map { index, clone -> [String: Any] in
            var entry: [String: Any] = [
                "fingerprint": "fake\(index)",
                "mass": clone.mass,
                "lineSpan": clone.spans.first?.lines.count ?? 0,
                "instances": clone.spans.map { span in
                    [
                        "path": span.path,
                        "startLine": span.lines.lowerBound,
                        "startColumn": 1,
                        "endLine": span.lines.upperBound,
                        "endColumn": endColumn
                    ]
                }
            ]
            if run == "--type3" {
                entry["similarity"] = similarity
            }
            return entry
        }
        let document: [String: Any] = [
            "tool": "swift-clone-detector", "version": "0.1.0", "duplicatedLines": 0, "clones": classes
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// The lines, from 1, from the first holding `start` to the next
    /// holding `end` in `source`: from the first line when no line holds
    /// `start`, and that line alone when none after it holds `end`.
    static func lines(from start: String, to end: String, in source: String) -> ClosedRange<Int> {
        let lines = source.components(separatedBy: "\n")
        let first = lines.firstIndex { $0.contains(start) } ?? 0
        let last = lines[first...].firstIndex { $0.contains(end) } ?? first
        return (first + 1)...(last + 1)
    }

    /// Has the detector report `clones` from now on.
    func report(_ clones: [FakeClone]) throws {
        let directory = tool.deletingLastPathComponent()
        for run in Self.runs {
            let reported = run == "--type1" ? clones.filter(\.exact) : clones.filter { $0.run == run }
            let file = directory.appendingPathComponent("out\(run)")
            try Self.json(reported, run: run).write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// A workspace on the repository, with its store in `.swiftstats/`,
    /// finding the fake detector when `withClones` is set and no tool otherwise.
    func workspace(withClones: Bool) throws -> SnapshotWorkspace {
        try SnapshotWorkspace(
            packageRoot: repository.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: HistoryRepository.DiskDescriber(),
            tools: withClones ? CloneHarness.locator(tool) : SnapshotHarness.noTools
        )
    }

    /// Writes `files` and commits them as `message` on `day`.
    @discardableResult
    func commit(_ files: [String: String], _ message: String, day: Int) throws -> String {
        try repository.write(files)
        return try repository.commit(message, day: day)
    }

    /// Scans the working tree with the fake detector and returns the
    /// stored snapshot's id.
    @discardableResult
    func scan() throws -> Int64 {
        try scan(withClones: true)
    }

    /// Scans the working tree, with the fake detector when `withClones` is
    /// set, and returns the stored snapshot's id.
    @discardableResult
    func scan(withClones: Bool) throws -> Int64 {
        try workspace(withClones: withClones).scanWorkingTree().id
    }

    /// The signal `name` of snapshot `id`, as `report` computes it.
    func signal(_ name: SignalName, id: Int64) throws -> SignalResult {
        let signals = try workspace(withClones: true).signals(id: id)
        guard let signal = signals.first(where: { $0.name == name }) else {
            throw ScanError.commandFailed("signals", -1, "no \(name.rawValue)")
        }
        return signal
    }

    /// Removes the repository and the fake detector.
    func remove() {
        repository.remove()
        CloneHarness.remove(tool)
    }
}
