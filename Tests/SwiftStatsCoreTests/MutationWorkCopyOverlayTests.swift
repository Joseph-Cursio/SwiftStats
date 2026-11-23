import Foundation
@testable import SwiftStatsCore
import Testing

/// The edges of the overlay that makes the copy SwiftMutator runs in the
/// scanned tree (M6, design §1.2 steps 2–3 and 6): changes listed against
/// the commit the scan read, not a later HEAD; a package in a folder its
/// repository ignores copied whole, as SwiftMutator walks it; deletions
/// applied before copies, so a case-only rename and a file replaced by a
/// folder come out right; the work tree's pins above the package; names
/// git prints that aren't UTF-8 failing the copy; SwiftMutator's listing
/// of a workspace's `Package.resolved`; and the git that writes the copy
/// running without the variables that name a repository.
@Suite("Mutation work copy overlay")
struct MutationWorkCopyOverlayTests {
    /// The library file most tests scan.
    private static let library = "Sources/Lib/A.swift"

    @Test("a commit made after the scan read its state still lands in the copy, as the work tree holds it")
    func headMovedAfterScan() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([Self.library: WorkCopyHarness.swift, "Resources/data.json": "one\n"])
        let scannedCommit = try repository.commit("one", day: 0)
        let state = GitReader.read(packageRoot: repository.root)
        try repository.write(["Resources/data.json": "two\n", "Resources/added.json": "added\n"])
        try repository.commit("two", day: 1)

        let (_, copy) = try WorkCopyHarness.copy(
            repository.root,
            git: state,
            scanning: [Self.library],
            ignoring: []
        )

        #expect(try repository.git(["-C", copy.project.path, "rev-parse", "HEAD"]) == scannedCommit)
        #expect(WorkCopyHarness.entries(of: copy.project) == [
            "Package.swift", "Resources/added.json", "Resources/data.json", Self.library
        ])
        #expect(try WorkCopyHarness.text("Resources/data.json", in: copy.project) == "two\n")
    }

    @Test("a package in a folder its repository ignores is copied whole, its resources included")
    func ignoredPackageFolder() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([".gitignore": "*\n!.gitignore\n!.zshrc\n", ".zshrc": "zsh\n"])
        try repository.commit("one", day: 0)
        let packageRoot = repository.root.appendingPathComponent("code/Pkg")
        try repository.write([
            "code/Pkg/Package.swift": "// swift-tools-version: 6.0\n",
            "code/Pkg/\(Self.library)": WorkCopyHarness.swift,
            "code/Pkg/Resources/data.json": "{}\n"
        ])
        let state = GitReader.read(packageRoot: packageRoot)
        #expect(state.commit != nil && state.packagePath == "code/Pkg")

        let (_, copy) = try WorkCopyHarness.copy(packageRoot, scanning: [Self.library], ignoring: [])

        #expect(MutationWorkCopy.projectPath(packageRoot: packageRoot, git: state) == "Pkg")
        #expect(
            WorkCopyHarness.realPath(copy.project) == WorkCopyHarness.realPath(copy.work.appendingPathComponent("Pkg"))
        )
        #expect(WorkCopyHarness.entries(of: copy.work) == [
            "Pkg/Package.swift", "Pkg/Resources/data.json", "Pkg/\(Self.library)"
        ])
    }

    @Test("a staged case-only rename leaves only the new name in the copy")
    func caseOnlyRename() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/signs.swift": WorkCopyHarness.swift])
        try repository.commit("one", day: 0)
        try repository.move("Sources/Lib/signs.swift", to: "Sources/Lib/Signs.swift")

        let (_, copy) = try WorkCopyHarness.copy(
            repository.root,
            scanning: ["Sources/Lib/Signs.swift"],
            ignoring: []
        )

        #expect(WorkCopyHarness.entries(of: copy.project) == ["Package.swift", "Sources/Lib/Signs.swift"])
        #expect(copy.fixedFiles == 0)
    }

    @Test("a tracked file replaced by a folder of files is that folder in the copy")
    func fileReplacedByFolder() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Gen": "generated\n"])
        try repository.commit("one", day: 0)
        try FileManager.default.removeItem(at: repository.root.appendingPathComponent("Sources/Gen"))
        try repository.write(["Sources/Gen/X.swift": WorkCopyHarness.swift])

        let (_, copy) = try WorkCopyHarness.copy(repository.root, scanning: ["Sources/Gen/X.swift"], ignoring: [])

        #expect(WorkCopyHarness.entries(of: copy.project) == ["Package.swift", "Sources/Gen/X.swift"])
    }

    @Test("the work tree's pins above the package are the copy's: an edited one as edited, a deleted one gone")
    func pinsAbovePackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            ".swift-version": "6.3\n",
            "Packages/.swift-version": "6.3\n",
            "Packages/Pkg/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Pkg/\(Self.library)": WorkCopyHarness.swift
        ])
        try repository.commit("one", day: 0)
        try repository.write([".swift-version": "6.4\n"])
        try FileManager.default.removeItem(at: repository.root.appendingPathComponent("Packages/.swift-version"))
        let packageRoot = repository.root.appendingPathComponent("Packages/Pkg")

        let (_, copy) = try WorkCopyHarness.copy(packageRoot, scanning: [Self.library], ignoring: [])

        let clone = copy.work.appendingPathComponent(repository.root.lastPathComponent)
        #expect(try WorkCopyHarness.text(".swift-version", in: clone) == "6.4\n")
        #expect(WorkCopyHarness.entries(of: clone) == [
            ".swift-version", "Package.swift", "Packages/Pkg/Package.swift", "Packages/Pkg/\(Self.library)"
        ])
    }

    @Test("a path git prints that isn't UTF-8 fails the copy, counted, rather than being left out")
    func pathsNotUTF8() throws {
        let data = Data("Sources/A.swift".utf8) + Data([0]) + Data("bad".utf8) + Data([0xFF, 0])
        let failure = MutationFailure(description: "making the copy failed: git lists paths that aren't UTF-8: 1 of 2")

        #expect(throws: failure) {
            try MutationWorkCopy.decodedPaths(data)
        }
        #expect(try MutationWorkCopy.decodedPaths(Data("a b\0c:d\0".utf8)) == ["a b", "c:d"])
    }

    @Test(
        "SwiftMutator lists Swift files, pins and the root or a workspace's Package.resolved however git ignores them",
        arguments: [
            ("Sources/Lib/A.swift", true),
            ("Deep/.swift-version", true),
            ("Package.resolved", true),
            ("App.xcworkspace/xcshareddata/swiftpm/Package.resolved", true),
            ("App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", true),
            ("Nested/Package.resolved", false),
            ("xcshareddata/swiftpm/Package.resolved", false),
            ("App.xcworkspace/swiftpm/Package.resolved", false),
            ("App.xcodeproj/xcshareddata/swiftpm/Package.resolved", false),
            ("Resources/data.json", false)
        ]
    )
    func alwaysListed(path: String, isListed: Bool) {
        #expect(MutationProjectFiles.isAlwaysListed(path) == isListed)
    }

    @Test("the variables the copy's git runs without are the ones git says name a repository")
    func repositoryVariables() throws {
        let data = try ProcessRunner.run(
            executable: GitReader.git,
            arguments: ["rev-parse", "--local-env-vars"],
            in: FileManager.default.temporaryDirectory
        )
        let listed = (String(bytes: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline).map(String.init)

        #expect(Set(listed) == MutationWorkCopy.repositoryVariables)
    }

    @Test("a command run without some variables doesn't see them, and sees the ones added")
    func removedVariables() throws {
        #expect(ProcessInfo.processInfo.environment["HOME"] != nil)

        let data = try ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: [],
            in: FileManager.default.temporaryDirectory,
            environment: ["SWIFTSTATS_ADDED": "1"],
            removing: ["HOME"]
        )
        let lines = (String(bytes: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline)

        #expect(lines.contains("SWIFTSTATS_ADDED=1"))
        #expect(lines.contains { $0.hasPrefix("HOME=") } == false)
    }
}
