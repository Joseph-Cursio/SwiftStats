import Foundation
@testable import SwiftStatsCore
import Testing

/// Which `.swift-version` SwiftInferProperties' copy gets and the options
/// record (PRD §7.11): the package's own, else the nearest above it in its
/// repository, which an export of a nested package carries just above it;
/// outside a repository, the nearest above it as far as swiftly looks.
@Suite("Toolchain pins")
struct ToolchainPinTests {
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
}
