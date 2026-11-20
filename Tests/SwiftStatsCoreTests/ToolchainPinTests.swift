import Foundation
@testable import SwiftStatsCore
import Testing

/// Which `.swift-version` SwiftInferProperties' copy gets and the options
/// record (PRD §7.11): the package's own, else the nearest above it in its
/// repository, which an export of a nested package carries just above it;
/// outside a repository, the nearest above it as far as swiftly looks.
@Suite("Toolchain pins")
struct ToolchainPinTests {
    /// The note on a backfill step scanned only once its pins were removed.
    private static let withoutPin = "scanned without its .swift-version toolchain pin"

    /// Commits a nested package `Packages/Inner` twice in `repository`: first
    /// under a repository pin no install has, then under one that is
    /// installed, with a function added. Returns the commits, oldest first.
    private static func commitStalePin(in repository: HistoryRepository) throws -> [String] {
        try repository.write([
            ".swift-version": "\(PinRefusingDescriber.uninstalled)\n",
            "Packages/Inner/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Inner/Sources/Inner/One.swift": "func one() -> Int {\n    1\n}\n"
        ])
        let old = try repository.commit("Old pin", day: 0)
        try repository.write([
            ".swift-version": "6.4.1\n",
            "Packages/Inner/Sources/Inner/Two.swift": "func two() -> Int {\n    2\n}\n"
        ])
        let new = try repository.commit("New pin", day: 1)
        return [old, new]
    }

    /// A workspace on `Packages/Inner` whose describing fails under the
    /// uninstalled pin.
    private static func innerWorkspace(_ repository: HistoryRepository) throws -> SnapshotWorkspace {
        try SnapshotWorkspace(
            packageRoot: repository.root.appendingPathComponent("Packages/Inner"),
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: PinRefusingDescriber(),
            tools: SnapshotHarness.noTools
        )
    }

    @Test("""
        a package with no toolchain pin of its own gets the nearest one in its repository, and so does an \
        export of it, which records the same options
        """)
    func nearestToolchainPin() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            ".swift-version": "6.4.1\n",
            "Packages/Inner/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Inner/Sources/Inner/One.swift": "func one() -> Int {\n    1\n}\n"
        ])
        let commit = try repository.commit("one", day: 0)
        let tool = try FakeTool.makeIndexer(
            indexes: ["Inner": PropertyHarness.emptyIndex],
            errors: [:],
            statuses: [:],
            delays: [:]
        )
        defer { PropertyHarness.remove(tool) }
        let scanner = PackageScanner(describer: HistoryRepository.DiskDescriber(), tools: PropertyHarness.locator(tool))

        let inner = repository.root.appendingPathComponent("Packages/Inner")
        let report = try scanner.scan(packageAt: inner)
        let pinned = FakeTool.log("swift-version-Inner.txt", of: tool)
        let pinLog = tool.deletingLastPathComponent().appendingPathComponent("swift-version-Inner.txt")
        try FileManager.default.removeItem(at: pinLog)
        let exported = try RevisionExport.export(commit: commit, packagePath: "Packages/Inner", from: inner)
        defer { try? FileManager.default.removeItem(at: RevisionExport.workDirectory(of: exported)) }
        let exportReport = try scanner.scan(packageAt: exported)

        #expect(PropertyHarness.status(report)?.state == .ran)
        #expect(pinned == ["6.4.1"])
        #expect(PropertyHarness.status(report)?.options.contains(".swift-version: 6.4.1") == true)
        #expect(PropertyHarness.status(exportReport)?.state == .ran)
        #expect(FakeTool.log("swift-version-Inner.txt", of: tool) == ["6.4.1"])
        #expect(PropertyHarness.status(exportReport)?.options == PropertyHarness.status(report)?.options)
        #expect(FileManager.default.fileExists(atPath: exported.appendingPathComponent(".swift-version").path) == false)
    }

    @Test("outside a repository, a package gets the nearest pin above it, and none when there is none")
    func outsideRepository() throws {
        let outer = try SnapshotHarness.temporaryDirectory("Pinned")
        defer { try? FileManager.default.removeItem(at: outer) }
        let package = outer.appendingPathComponent("Deep/Pkg")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let bare = try SnapshotHarness.temporaryDirectory("Bare")
        defer { try? FileManager.default.removeItem(at: bare) }
        try Data("6.4.1\n".utf8).write(to: outer.appendingPathComponent(".swift-version"))

        #expect(SwiftInferCopy.toolchainOption(root: package) == ".swift-version: 6.4.1")
        #expect(SwiftInferCopy.toolchainPin(for: bare) == nil)
        #expect(SwiftInferCopy.toolchainOption(root: bare) == ".swift-version: absent")
    }

    @Test("""
        backfill scans a nested package's commit whose inherited pin no longer installs by removing that pin, \
        and an export still carries the inherited pin
        """)
    func backfillWithoutInheritedPin() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let commits = try Self.commitStalePin(in: repository)
        let workspace = try Self.innerWorkspace(repository)

        let steps = try workspace.backfill(
            BackfillPlan(selection: .every(1), since: nil, maximumCommits: nil, rerun: false, withTools: false)
        ) { _ in
            // Progress isn't checked here.
        }
        let exported = try RevisionExport.export(
            commit: commits[1],
            packagePath: "Packages/Inner",
            from: repository.root
        )
        defer { try? FileManager.default.removeItem(at: RevisionExport.workDirectory(of: exported)) }
        let inherited = RevisionExport.workDirectory(of: exported).appendingPathComponent(".swift-version")

        #expect(steps.map(\.commit) == commits)
        #expect(steps.map(\.action) == [.scanned, .scanned])
        #expect(steps.map(\.note) == [Self.withoutPin, nil])
        #expect(RevisionExport.toolchainPins(of: exported) == [inherited])
        #expect(try String(contentsOf: inherited, encoding: .utf8) == "6.4.1\n")
    }

    @Test("diff scans a nested package's commit whose inherited pin no longer installs by removing that pin")
    func diffWithoutInheritedPin() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let commits = try Self.commitStalePin(in: repository)
        let workspace = try Self.innerWorkspace(repository)

        let ids = try workspace.diffSnapshotIDs(older: commits[0], newer: nil, includeDirty: false, rescan: false)

        let stored = try workspace.store.snapshotID(
            packagePath: "Packages/Inner",
            commit: commits[0],
            isDirty: false
        )
        #expect(ids.older == stored)
        #expect(ids.older != ids.newer)
    }
}
