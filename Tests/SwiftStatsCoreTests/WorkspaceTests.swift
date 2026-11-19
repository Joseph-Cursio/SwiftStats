//
//  WorkspaceTests.swift
//  SwiftStatsCoreTests
//
//  How `report` and `diff` pick snapshots (PRD §6.2, §10): a dirty snapshot
//  stands for the working tree only while its changes are the tree's, the
//  same commit is never rescanned twice in one diff, and a store kept in the
//  package doesn't make the tree dirty.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Workspace", .serialized)
struct WorkspaceTests {
    /// The diff fixture's newer tree.
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Diff/after")

    /// A repository holding the fixture, committed, plus `extra` files
    /// committed with it, and a workspace on it.
    private static func repository(extra: [String: String]) throws -> (root: URL, workspace: SnapshotWorkspace) {
        let root = try SnapshotHarness.temporaryDirectory("Workspace")
        try ".build/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        for item in ["Package.swift", "Sources"] {
            let target = root.appendingPathComponent(item)
            try FileManager.default.copyItem(at: fixture.appendingPathComponent(item), to: target)
        }
        for (path, text) in extra {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        try SnapshotHarness.runGit(["init", "--quiet", "--initial-branch=main"], in: root)
        try SnapshotHarness.runGit(["add", "--all"], in: root)
        try SnapshotHarness.runGit(["commit", "--quiet", "--message", "one"], in: root)
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

    /// Writes a one-function file `name.swift` into the fixture's module.
    private static func add(_ name: String, in root: URL) throws {
        let source = "func \(name)() -> Int {\n    let value = 1\n    return value\n}\n"
        let file = root.appendingPathComponent("Sources/Shapes/\(name).swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test("a dirty snapshot stands for the working tree only while the tree's changes are the same")
    func staleDirtySnapshot() throws {
        let (root, workspace) = try Self.repository(extra: [:])
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.add("gamma", in: root)
        let scanned = try workspace.scanWorkingTree().id
        let current = try workspace.reportSnapshotID(revision: nil)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/Shapes/gamma.swift"))
        try Self.add("delta", in: root)

        #expect(current == scanned)
        #expect(throws: StoreError.workingTreeChanged("Shapes")) {
            try workspace.reportSnapshotID(revision: nil)
        }
        let ids = try workspace.diffSnapshotIDs(older: "HEAD", newer: nil, includeDirty: true, rescan: false)
        let names = try workspace.store.load(id: ids.newer).functions.map(\.name)
        #expect(names.contains("delta"))
        #expect(names.contains("gamma") == false)
    }

    @Test("rescanning a diff of one commit with itself scans it once")
    func rescanSameCommit() throws {
        let (root, workspace) = try Self.repository(extra: [:])
        defer { try? FileManager.default.removeItem(at: root) }

        let ids = try workspace.diffSnapshotIDs(older: "HEAD", newer: nil, includeDirty: false, rescan: true)
        let diff = SnapshotDiff.diff(try workspace.store.load(id: ids.older), try workspace.store.load(id: ids.newer))

        #expect(ids.older == ids.newer)
        #expect(diff.isEmpty)
    }

    @Test("a store kept in the package by store: doesn't make a clean tree dirty")
    func storeInPackage() throws {
        let configuration = ".swiftstats.yml"
        let (root, workspace) = try Self.repository(extra: [configuration: "store: stats/db.sqlite\n"])
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try workspace.scanWorkingTree().snapshot
        let second = try workspace.scanWorkingTree().snapshot

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("stats/db.sqlite").path))
        #expect(first.info.git.isDirty == false)
        #expect(second.info.git.isDirty == false)
    }
}
