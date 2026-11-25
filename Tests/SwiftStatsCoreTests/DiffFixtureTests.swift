//
//  DiffFixtureTests.swift
//  SwiftStatsCoreTests
//
//  PRD M2 done-when 2: on a commit that adds, changes, moves and deletes one
//  function each (Tests/Fixtures/Diff/before → after), the diff shows
//  exactly those four, and the move shows as a move. The repository is made
//  at test time; `diff` scans the older commit from a `git archive` export
//  and the newer one in place. The `Spelling` and `Glossary` modules hold
//  M7's cases for the index (a spelling change, a retargeted typealias, and
//  two `size(of:)` overloads whose keys collide, `Foundation.Data` against
//  `Glossary.Data`, each moved to another file in `after`, so both collision
//  suffixes change), so these tests read the `Shapes` module alone.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Diff fixture", .serialized)
struct DiffFixtureTests {
    /// The fixture's two trees.
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Diff")

    /// A repository with `before` committed, then `after`, and a workspace on it.
    private static func repository() throws -> (root: URL, workspace: SnapshotWorkspace) {
        let root = try SnapshotHarness.temporaryDirectory("DiffFixture")
        try ".build/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try SnapshotHarness.runGit(["init", "--quiet", "--initial-branch=main"], in: root)
        for side in ["before", "after"] {
            let sources = root.appendingPathComponent("Sources")
            try? FileManager.default.removeItem(at: sources)
            for item in ["Package.swift", "Sources"] {
                let target = root.appendingPathComponent(item)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: fixture.appendingPathComponent("\(side)/\(item)"), to: target)
            }
            try SnapshotHarness.runGit(["add", "--all"], in: root)
            try SnapshotHarness.runGit(["commit", "--quiet", "--message", side], in: root)
        }
        let workspace = try SnapshotWorkspace(
            packageRoot: root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: SwiftPMPackageDescriber(),
            tools: SnapshotHarness.noTools
        )
        return (root, workspace)
    }

    @Test("adding, changing, moving and deleting one function each shows exactly those four")
    func fourChanges() throws {
        let (root, workspace) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: root) }

        let ids = try workspace.diffSnapshotIDs(older: "HEAD~1", newer: nil, includeDirty: false, rescan: false)
        let diff = SnapshotDiff.diff(try workspace.store.load(id: ids.older), try workspace.store.load(id: ids.newer))

        let shapes = diff.families.filter { $0.key.hasPrefix("Shapes::") }
        let summary = shapes.map { "\($0.statuses.map(\.rawValue).joined(separator: "+")) \($0.key)" }
        #expect(summary == [
            "changed Shapes::Square::func area() -> Int",
            "added Shapes::func diagonal(of: Square) -> Double",
            "removed Shapes::func legacyDescription(of: Square) -> String",
            "moved Shapes::func perimeter(of: Square) -> Int"
        ].sorted { $0.split(separator: " ")[1] < $1.split(separator: " ")[1] })
        let moved = try #require(shapes.first { $0.statuses == [.moved] })
        #expect(moved.oldFile == "Sources/Shapes/Perimeter.swift")
        #expect(moved.newFile == "Sources/Shapes/Measure.swift")
        #expect(moved.matchedBy == .key)
        #expect(moved.records == [
            "Shapes::func perimeter(of: Square) -> Int",
            "Shapes::func perimeter(of: Square) -> Int / func edges() -> Int"
        ])
        #expect(moved.changedRecords.isEmpty)
        // Only the changed function's own metrics move: `area` went from 2
        // stripped lines in its body plus the signature (4 in all) to 6, and
        // gained a `guard` (cognitive 0 → 1).
        let functions = diff.functions.filter { $0.key.hasPrefix("Shapes::") }
        #expect(functions.map(\.key) == ["Shapes::Square::func area() -> Int"])
        let area = Dictionary(uniqueKeysWithValues: try #require(functions.first).metrics.map { ($0.metric, $0) })
        #expect(area["strippedLines"]?.before == 4)
        #expect(area["strippedLines"]?.after == 6)
        #expect(area["strippedLines"]?.verdict == .worse)
        #expect(area["cognitive"]?.before == 0)
        #expect(area["cognitive"]?.after == 1)
        #expect(diff.warnings.isEmpty)
    }

    @Test("roll-up deltas are expected, and are not function changes")
    func rollups() throws {
        let (root, workspace) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: root) }

        let ids = try workspace.diffSnapshotIDs(older: "HEAD~1", newer: "HEAD", includeDirty: false, rescan: false)
        let diff = SnapshotDiff.diff(try workspace.store.load(id: ids.older), try workspace.store.load(id: ids.newer))
        let module = diff.rollups.filter { $0.scope == .module && $0.name == "Shapes" }
        let changed = Dictionary(uniqueKeysWithValues: module.map { ($0.delta.metric, $0.delta) })

        // One `func` removed and one added: the count of each kind holds.
        #expect(changed["functions.func"] == nil)
        // Function lines, counted by hand: before, init 3 + area 4 +
        // perimeter 8 (its nested edges included) + edges 4 +
        // legacyDescription 5 = 24; after, init 3 + area 6 + diagonal 5 +
        // perimeter 8 + edges 4 = 26. The move changes neither.
        #expect(changed["functionLength.total"]?.before == 24)
        #expect(changed["functionLength.total"]?.after == 26)
        #expect(module.allSatisfy { $0.collector == SwiftStatsCollector.name })
        #expect(diff.rollups.contains { $0.scope == .project && $0.name == "production" })
    }

    @Test("the older commit was scanned from an export, leaving no state in the repository")
    func noRepositoryState() throws {
        let (root, workspace) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: root) }

        let ids = try workspace.diffSnapshotIDs(older: "HEAD~1", newer: nil, includeDirty: false, rescan: false)
        let again = try workspace.diffSnapshotIDs(older: "HEAD~1", newer: nil, includeDirty: false, rescan: false)

        #expect(ids == again)
        #expect(try SnapshotHarness.runGit(["worktree", "list"], in: root).split(separator: "\n").count == 1)
        #expect(try SnapshotHarness.runGit(["status", "--porcelain"], in: root).isEmpty)
        let older = try workspace.store.info(id: ids.older)
        #expect(older.git.commit == (try SnapshotHarness.runGit(["rev-parse", "HEAD~1"], in: root)))
    }
}
