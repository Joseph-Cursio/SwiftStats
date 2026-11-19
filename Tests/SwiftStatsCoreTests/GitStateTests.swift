import Foundation
@testable import SwiftStatsCore
import Testing

/// Reading git state and exporting revisions (PRD §6.2, §10).
@Suite("Git state", .serialized)
struct GitStateTests {
    /// Writes `text` to `path` under `directory`, creating folders.
    private static func write(_ text: String, _ path: String, in directory: URL) throws {
        let file = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// A repository holding a package at `Pkg/`, with one commit.
    private static func repository() throws -> URL {
        let root = try SnapshotHarness.temporaryDirectory("GitState")
        let package = root.appendingPathComponent("Pkg")
        try write("// manifest\n", "Package.swift", in: package)
        try write("func one() {}\n", "Sources/Lib/a.swift", in: package)
        try write("elsewhere\n", "README", in: root)
        try SnapshotHarness.runGit(["init", "--quiet", "--initial-branch=main"], in: root)
        try SnapshotHarness.runGit(["add", "--all"], in: root)
        try SnapshotHarness.runGit(["commit", "--quiet", "--message", "one"], in: root)
        return root
    }

    @Test("a package in a subdirectory: its path, commit and branch; dirtiness only from its own directory")
    func subdirectory() throws {
        let root = try Self.repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Pkg")
        let head = try SnapshotHarness.runGit(["rev-parse", "HEAD"], in: root)

        let clean = GitReader.read(packageRoot: package)
        try Self.write("changed\n", "README", in: root)
        let outsideChange = GitReader.read(packageRoot: package)
        try Self.write("x", ".swiftstats/stats.sqlite", in: package)
        let storeOnly = GitReader.read(packageRoot: package)
        try Self.write("func two() {}\n", "Sources/Lib/b.swift", in: package)
        let untracked = GitReader.read(packageRoot: package)

        #expect(clean == GitState(commit: head, branch: "main", isDirty: false, dirtyHash: nil, packagePath: "Pkg"))
        #expect(outsideChange.isDirty == false)
        #expect(storeOnly.isDirty == false)
        #expect(untracked.isDirty)
        #expect(untracked.dirtyHash?.count == 64)
    }

    @Test("the dirty check ignores the user's diff configuration, and a store kept in the package")
    func dirtyCheckIndependence() throws {
        let root = try Self.repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Pkg")
        // An external diff tool that prints nothing would hide every change.
        try SnapshotHarness.runGit(["config", "diff.external", "/usr/bin/true"], in: root)

        try Self.write("x", "stats/db.sqlite", in: package)
        let storeOnly = GitReader.read(packageRoot: package, ignoring: ["stats/db.sqlite"])
        try Self.write("func edited() {}\n", "Sources/Lib/a.swift", in: package)
        let edited = GitReader.read(packageRoot: package, ignoring: ["stats/db.sqlite"])

        #expect(storeOnly.isDirty == false)
        #expect(edited.isDirty)
    }

    @Test("an export keeps export-ignore paths, which git archive would drop")
    func exportIgnore() throws {
        let root = try Self.repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Pkg")
        try Self.write("func kept() {}\n", "Sources/Lib/K.swift", in: package)
        try Self.write("K.swift export-ignore\n", "Sources/Lib/.gitattributes", in: package)
        try SnapshotHarness.runGit(["add", "--all"], in: root)
        try SnapshotHarness.runGit(["commit", "--quiet", "--message", "two"], in: root)
        let commit = try SnapshotHarness.runGit(["rev-parse", "HEAD"], in: root)

        let exported = try RevisionExport.export(commit: commit, packagePath: "Pkg", from: package)
        defer { try? FileManager.default.removeItem(at: RevisionExport.workDirectory(of: exported)) }

        #expect(FileManager.default.fileExists(atPath: exported.appendingPathComponent("Sources/Lib/K.swift").path))
        #expect(try SnapshotHarness.runGit(["status", "--porcelain"], in: root).isEmpty)
    }

    @Test("a detached HEAD has no branch; a directory outside git has no state")
    func detachedAndOutside() throws {
        let root = try Self.repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try SnapshotHarness.temporaryDirectory("Outside")
        defer { try? FileManager.default.removeItem(at: outside) }

        try SnapshotHarness.runGit(["checkout", "--quiet", "--detach"], in: root)

        #expect(GitReader.read(packageRoot: root.appendingPathComponent("Pkg")).branch == nil)
        #expect(GitReader.read(packageRoot: outside) == .outsideGit)
    }

    @Test("""
        an export holds the package as of the commit; an annotated tag names its commit; \
        a missing package is an error
        """)
    func export() throws {
        let root = try Self.repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Pkg")
        let first = try SnapshotHarness.runGit(["rev-parse", "HEAD"], in: root)
        try SnapshotHarness.runGit(["tag", "--annotate", "v1", "--message", "one"], in: root)
        try Self.write("func changed() {}\n", "Sources/Lib/a.swift", in: package)
        try SnapshotHarness.runGit(["commit", "--quiet", "--all", "--message", "two"], in: root)

        let commit = try #require(RevisionExport.commit(of: "v1", in: package))
        let exported = try RevisionExport.export(commit: commit, packagePath: "Pkg", from: package)
        defer { try? FileManager.default.removeItem(at: RevisionExport.workDirectory(of: exported)) }

        #expect(commit == first)
        let source = try String(contentsOf: exported.appendingPathComponent("Sources/Lib/a.swift"), encoding: .utf8)
        #expect(source == "func one() {}\n")
        #expect(FileManager.default.fileExists(atPath: exported.appendingPathComponent("README").path) == false)
        #expect(RevisionExport.commit(of: "no-such-branch", in: package) == nil)
        #expect(throws: ScanError.self) {
            try RevisionExport.export(commit: commit, packagePath: "Missing", from: package)
        }
    }
}
