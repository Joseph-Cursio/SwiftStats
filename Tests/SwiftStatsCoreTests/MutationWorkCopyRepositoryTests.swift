import Foundation
@testable import SwiftStatsCore
import Testing

/// What the copy SwiftMutator runs in holds outside the package's own
/// changes (M6, design §1.2, as built): a package below the top level
/// finds a local dependency beside it as the work tree holds it, changes
/// and untracked files included; and tracked files git checks out with
/// other bytes without listing them as changed (`skip-worktree`,
/// `assume-unchanged`, a filter whose configuration isn't cloned) are
/// taken from the work tree and counted.
@Suite("Mutation work copy repository")
struct MutationWorkCopyRepositoryTests {
    /// The package's own source file.
    private static let appSource = "Sources/App/App.swift"

    @Test("""
        a package below the top level finds a local dependency beside it as the work tree holds it: changed, \
        deleted and untracked files, nothing in its build folder
        """)
    func siblingDependency() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Packages/App/Package.swift": """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "App", dependencies: [.package(path: "../Core")])

            """,
            "Packages/App/\(Self.appSource)": WorkCopyHarness.swift,
            "Packages/Core/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Core/Sources/Core/Core.swift": WorkCopyHarness.swift,
            "Packages/Core/Sources/Core/Gone.swift": WorkCopyHarness.swift
        ])
        try repository.commit("one", day: 0)
        try repository.write([
            "Packages/Core/Sources/Core/Core.swift": WorkCopyHarness.changed,
            "Packages/Core/Sources/Core/New.swift": WorkCopyHarness.swift,
            "Packages/Core/.build/Debug.swift": WorkCopyHarness.swift
        ])
        let gone = repository.root.appendingPathComponent("Packages/Core/Sources/Core/Gone.swift")
        try FileManager.default.removeItem(at: gone)
        let packageRoot = repository.root.appendingPathComponent("Packages/App")

        let (_, copy) = try WorkCopyHarness.copy(packageRoot, scanning: [Self.appSource], ignoring: [])

        let core = copy.project.deletingLastPathComponent().appendingPathComponent("Core")
        #expect(WorkCopyHarness.entries(of: core) == [
            "Package.swift", "Sources/Core/Core.swift", "Sources/Core/New.swift"
        ])
        #expect(try WorkCopyHarness.text("Sources/Core/Core.swift", in: core) == WorkCopyHarness.changed)
        #expect(WorkCopyHarness.entries(of: copy.project) == ["Package.swift", Self.appSource])
        #expect(copy.fixedFiles == 0)
        #expect(try repository.git(["status", "--porcelain"]).contains(".swiftstats") == false)
    }

    @Test("""
        tracked files git checks out with other bytes and lists as unchanged (skip-worktree, assume-unchanged, a \
        filter configured only in the source) are taken from the work tree and counted
        """)
    func flaggedFiles() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        // A filter configured in the source's own .git/config, as git-crypt
        // is, which the copy's clone doesn't have.
        try repository.git(["config", "filter.fake.clean", "sed s/content/pointer/"])
        try repository.git(["config", "filter.fake.smudge", "sed s/pointer/content/"])
        try repository.write([
            "Package.swift": "// committed\n",
            ".gitattributes": "secret.txt filter=fake\n",
            "secret.txt": "content\n",
            "Tests/Fixtures/data.txt": "committed\n",
            "Sources/Lib/A.swift": WorkCopyHarness.swift
        ])
        try repository.commit("one", day: 0)
        try #require(try repository.git(["show", "HEAD:secret.txt"]) == "pointer")
        try repository.git(["update-index", "--skip-worktree", "Package.swift"])
        try repository.git(["update-index", "--assume-unchanged", "Tests/Fixtures/data.txt"])
        try repository.write(["Package.swift": "// local override\n", "Tests/Fixtures/data.txt": "local\n"])
        try #require(try repository.git(["status", "--porcelain"]).isEmpty)

        let flagged = try MutationWorkCopy.flaggedPaths(of: repository.root)
        let (_, copy) = try WorkCopyHarness.copy(repository.root, scanning: ["Sources/Lib/A.swift"], ignoring: [])

        #expect(flagged == ["Package.swift", "Tests/Fixtures/data.txt", "secret.txt"])
        #expect(try WorkCopyHarness.text("Package.swift", in: copy.project) == "// local override\n")
        #expect(try WorkCopyHarness.text("Tests/Fixtures/data.txt", in: copy.project) == "local\n")
        #expect(try WorkCopyHarness.text("secret.txt", in: copy.project) == "content\n")
        #expect(copy.fixedFiles == 3)
    }
}
