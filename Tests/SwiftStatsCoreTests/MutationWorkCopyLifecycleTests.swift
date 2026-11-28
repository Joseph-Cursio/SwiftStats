import Foundation
@testable import SwiftStatsCore
import Testing

/// How the copy SwiftMutator runs in comes and goes (M6, design §1.2):
/// `build-cache/` moves into each copy and back, so it outlives every
/// run; a leftover `work/` is recovered with its build; a package outside
/// git is copied whole but for the folders SwiftMutator never lists; and a
/// copy that fails, from an edited file or git, leaves nothing behind and
/// names no path.
@Suite("Mutation work copy lifecycle")
struct MutationWorkCopyLifecycleTests {
    /// The library file the tests scan.
    private static let library = "Sources/Lib/A.swift"

    /// A repository holding the library file, committed.
    private static func repository() throws -> HistoryRepository {
        let repository = try HistoryRepository()
        try repository.write([library: WorkCopyHarness.swift])
        try repository.commit("one", day: 0)
        return repository
    }

    /// The text of the build marker in the folder at `url`.
    private static func marker(in url: URL) throws -> String {
        try WorkCopyHarness.text("marker", in: url)
    }

    @Test("build-cache moves into each copy and back, so it outlives every run")
    func buildCacheSurvives() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let directory = try MutationDirectory(packageRoot: repository.root)
        try WorkCopyHarness.build(at: directory.buildCache, marker: "warm")

        for _ in 1...2 {
            let (_, copy) = try WorkCopyHarness.copy(repository.root, scanning: [Self.library], ignoring: [])
            #expect(try Self.marker(in: copy.project.appendingPathComponent(".build")) == "warm")
            #expect(FileClone.exists(directory.buildCache) == false)

            try copy.finish(in: directory)

            #expect(try Self.marker(in: directory.buildCache) == "warm")
            #expect(FileClone.exists(directory.work) == false)
        }
        #expect(try repository.git(["status", "--porcelain"]).isEmpty)
    }

    @Test("a finished copy with no build of its own leaves build-cache as it was, absent")
    func noBuild() throws {
        let repository = try Self.repository()
        defer { repository.remove() }

        let (directory, copy) = try WorkCopyHarness.copy(repository.root, scanning: [Self.library], ignoring: [])
        try copy.finish(in: directory)

        #expect(FileClone.exists(directory.buildCache) == false)
        #expect(FileClone.exists(directory.work) == false)
    }

    @Test("a leftover work/ is removed, its build going back to build-cache unless one is there")
    func leftoverRecovered() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let directory = try MutationDirectory(packageRoot: repository.root)
        let git = GitReader.read(packageRoot: repository.root)
        let project = directory.work.appendingPathComponent(
            MutationWorkCopy.projectPath(packageRoot: repository.root, git: git)
        )
        let sideFolder = directory.work.appendingPathComponent("\(repository.root.lastPathComponent)_mutated.noindex")

        #expect(try MutationWorkCopy.recoverLeftover(packageRoot: repository.root, git: git, in: directory) == false)

        try WorkCopyHarness.build(at: project.appendingPathComponent(".build"), marker: "left")
        try WorkCopyHarness.build(at: sideFolder, marker: "side")
        #expect(try MutationWorkCopy.recoverLeftover(packageRoot: repository.root, git: git, in: directory))
        #expect(try Self.marker(in: directory.buildCache) == "left")
        #expect(FileClone.exists(directory.work) == false)

        try WorkCopyHarness.build(at: project.appendingPathComponent(".build"), marker: "older")
        #expect(try MutationWorkCopy.recoverLeftover(packageRoot: repository.root, git: git, in: directory))
        #expect(try Self.marker(in: directory.buildCache) == "left")
        #expect(FileClone.exists(directory.work) == false)
    }

    @Test("a copy is refused while a leftover work/ is in the way")
    func leftoverInTheWay() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let directory = try MutationDirectory(packageRoot: repository.root)
        try WorkCopyHarness.build(at: directory.work, marker: "left")

        let refusal = MutationFailure(description: "a copy from an earlier run is still in .swiftstats/mutation/work")
        #expect(throws: refusal) {
            try MutationWorkCopy.make(
                packageRoot: repository.root,
                git: GitReader.read(packageRoot: repository.root),
                scanned: [:],
                ignoring: [],
                in: directory
            )
        }
        #expect(try Self.marker(in: directory.work) == "left")
    }

    @Test("""
        outside git the package is copied whole, a nested checkout's files among it, but for the folders \
        SwiftMutator never lists and the store
        """)
    func outsideGit() throws {
        let package = try TemporaryPackage([
            Self.library: WorkCopyHarness.swift,
            "Resources/data.json": "{}\n",
            "Vendor/Dep/.git/HEAD": "ref: refs/heads/main\n",
            "Vendor/Dep/Dep.swift": WorkCopyHarness.swift,
            ".build/x.swift": WorkCopyHarness.swift,
            ".swiftpm/y.json": "{}\n",
            "Nested/.build/z.swift": WorkCopyHarness.swift,
            "stats.sqlite": "db",
            "stats.sqlite-wal": "wal"
        ])
        defer { package.remove() }
        try #require(GitReader.read(packageRoot: package.root) == .outsideGit)
        try FileManager.default.createDirectory(
            at: package.root.appendingPathComponent("Empty"),
            withIntermediateDirectories: true
        )
        let directory = try MutationDirectory(packageRoot: package.root)
        try WorkCopyHarness.build(at: directory.buildCache, marker: "warm")

        let (_, copy) = try WorkCopyHarness.copy(package.root, scanning: [Self.library], ignoring: ["stats.sqlite"])

        #expect(
            WorkCopyHarness.realPath(copy.project)
                == WorkCopyHarness.realPath(copy.work.appendingPathComponent(package.root.lastPathComponent))
        )
        #expect(WorkCopyHarness.entries(of: copy.project) == [
            ".build/marker", "Package.swift", "Resources/data.json", Self.library, "Vendor/Dep/Dep.swift"
        ])
        #expect(FileClone.isDirectory(copy.project.appendingPathComponent("Empty")))
        #expect(copy.fixedFiles == 0)
    }

    @Test("a file edited after the scan read it fails the copy naming it, leaving no work/ and build-cache as it was")
    func editedAfterScan() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let directory = try MutationDirectory(packageRoot: repository.root)
        try WorkCopyHarness.build(at: directory.buildCache, marker: "warm")
        let scanned = try WorkCopyHarness.scanned([Self.library], in: repository.root)
        try repository.write([Self.library: WorkCopyHarness.changed])

        #expect(throws: MutationFailure(description: "\(Self.library) changed after the scan read it; scan again")) {
            try MutationWorkCopy.make(
                packageRoot: repository.root,
                git: GitReader.read(packageRoot: repository.root),
                scanned: scanned,
                ignoring: [],
                in: directory
            )
        }
        #expect(FileClone.exists(directory.work) == false)
        #expect(try Self.marker(in: directory.buildCache) == "warm")
    }

    @Test("a git command that fails names itself and its status, with no path, and leaves no work/")
    func gitFailure() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let directory = try MutationDirectory(packageRoot: repository.root)
        let git = GitReader.read(packageRoot: repository.root)
        let missing = GitState(
            commit: String(repeating: "0", count: 40),
            branch: nil,
            isDirty: false,
            dirtyHash: nil,
            packagePath: git.packagePath
        )

        let failure = try #require(throws: MutationFailure.self) {
            try MutationWorkCopy.make(
                packageRoot: repository.root,
                git: missing,
                scanned: [:],
                ignoring: [],
                in: directory
            )
        }

        #expect(failure.description.hasPrefix("making the copy failed: git checkout exited 128"))
        #expect(failure.description.contains(WorkCopyHarness.realPath(repository.root)) == false)
        #expect(failure.description.contains(repository.root.path) == false)
        #expect(FileClone.exists(directory.work) == false)
    }
}
