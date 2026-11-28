import Foundation
@testable import SwiftStatsCore
import Testing

/// What the copy SwiftMutator runs in holds (M6, design §1.2), on
/// temporary repositories: a shared clone checked out at HEAD, the whole
/// tree even for a package below the top level, with the package's
/// changes and the Swift files git ignores laid over it, every scanned
/// file holding the bytes the scan read, links kept as links, and nothing
/// of it showing in the package's `git status`.
/// `MutationWorkCopyRepositoryTests` holds what lies outside the package.
@Suite("Mutation work copy")
struct MutationWorkCopyTests {
    /// The library file most tests scan.
    private static let library = "Sources/Lib/A.swift"

    /// What `git <arguments>` prints in `directory`, trimmed.
    private static func git(_ arguments: [String], in directory: URL) throws -> String {
        let data = try ProcessRunner.run(executable: GitReader.git, arguments: arguments, in: directory)
        return (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("a clean package is a shared clone at HEAD's commit that copies no object and leaves git status empty")
    func cleanPackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([Self.library: WorkCopyHarness.swift, "Tests/LibTests/T.swift": WorkCopyHarness.swift])
        let commit = try repository.commit("one", day: 0)

        let (_, copy) = try WorkCopyHarness.copy(
            repository.root,
            scanning: [Self.library, "Tests/LibTests/T.swift"],
            ignoring: []
        )

        #expect(WorkCopyHarness.entries(of: copy.project) == ["Package.swift", Self.library, "Tests/LibTests/T.swift"])
        #expect(copy.fixedFiles == 0)
        #expect(
            WorkCopyHarness.realPath(copy.project)
                == WorkCopyHarness.realPath(copy.work.appendingPathComponent(repository.root.lastPathComponent))
        )
        #expect(try Self.git(["rev-parse", "HEAD"], in: copy.project) == commit)
        #expect(FileClone.exists(copy.project.appendingPathComponent(".git/objects/info/alternates")))
        let objects = try Self.git(["count-objects", "-v"], in: copy.project).split(separator: "\n")
        #expect(objects.contains("count: 0") && objects.contains("packs: 0"))
        #expect(try repository.git(["status", "--porcelain"]).isEmpty)
    }

    @Test("a dirty package's changes are laid over the checkout: modified, deleted, untracked and ignored Swift files")
    func dirtyPackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            Self.library: WorkCopyHarness.swift,
            "Sources/Lib/B.swift": WorkCopyHarness.swift,
            ".gitignore": "Generated/\n*.log\n"
        ])
        try repository.commit("one", day: 0)
        try repository.write([
            Self.library: WorkCopyHarness.changed,
            "Sources/Lib/C.swift": WorkCopyHarness.swift,
            "notes.md": "notes\n",
            "Generated/G.swift": WorkCopyHarness.swift,
            "debug.log": "log\n",
            ".build/Debug.swift": WorkCopyHarness.swift
        ])
        try FileManager.default.removeItem(at: repository.root.appendingPathComponent("Sources/Lib/B.swift"))

        let (_, copy) = try WorkCopyHarness.copy(
            repository.root,
            scanning: [Self.library, "Sources/Lib/C.swift", "Generated/G.swift"],
            ignoring: []
        )

        #expect(WorkCopyHarness.entries(of: copy.project) == [
            ".gitignore", "Generated/G.swift", "Package.swift", Self.library, "Sources/Lib/C.swift", "notes.md"
        ])
        #expect(try WorkCopyHarness.text(Self.library, in: copy.project) == WorkCopyHarness.changed)
        #expect(copy.fixedFiles == 0)
        // Nothing under .swiftstats/, where the copy is.
        let status = try repository.git(["status", "--porcelain"])
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(status == [
            "M \(Self.library)", "D Sources/Lib/B.swift", "?? .build/", "?? Sources/Lib/C.swift", "?? notes.md"
        ])
    }

    @Test("a package below the top level is a full checkout: the pin above it and the folders beside it come too")
    func subdirectoryPackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            ".swift-version": "6.4\n",
            "Other/O.swift": WorkCopyHarness.swift,
            "Packages/Pkg/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Pkg/\(Self.library)": WorkCopyHarness.swift
        ])
        try repository.commit("one", day: 0)
        let packageRoot = repository.root.appendingPathComponent("Packages/Pkg")

        let (_, copy) = try WorkCopyHarness.copy(packageRoot, scanning: [Self.library], ignoring: [])

        let clone = copy.work.appendingPathComponent(repository.root.lastPathComponent)
        #expect(
            WorkCopyHarness.realPath(copy.project)
                == WorkCopyHarness.realPath(clone.appendingPathComponent("Packages/Pkg"))
        )
        #expect(WorkCopyHarness.entries(of: clone) == [
            ".swift-version", "Other/O.swift", "Package.swift", "Packages/Pkg/Package.swift",
            "Packages/Pkg/\(Self.library)"
        ])
        #expect(try repository.git(["status", "--porcelain"]).isEmpty)
    }

    @Test("""
        a nested package comes as files, without its build or an ignored checkout, with ignored Swift files but \
        not an ignored folder named like one
        """)
    func nestedPackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            ".gitignore": ".build/\nVendor/\nLocal.swift\nGen.swift/\n",
            "Nested/Helper/Package.swift": "// swift-tools-version: 6.0\n",
            "Nested/Helper/Sources/H/H.swift": WorkCopyHarness.swift
        ])
        try repository.commit("one", day: 0)
        try repository.write([
            "Nested/Helper/.build/debug/Gen.swift": WorkCopyHarness.swift,
            "Nested/Helper/Sources/H/Local.swift": WorkCopyHarness.swift,
            "Vendor/Clone/.git/HEAD": "ref: refs/heads/main\n",
            "Vendor/Clone/V.swift": WorkCopyHarness.swift,
            "Vendor/Loose/L.swift": WorkCopyHarness.swift,
            "Gen.swift/notes.txt": "notes\n"
        ])

        let (_, copy) = try WorkCopyHarness.copy(repository.root, scanning: [], ignoring: [])

        #expect(WorkCopyHarness.entries(of: copy.project) == [
            ".gitignore", "Nested/Helper/Package.swift", "Nested/Helper/Sources/H/H.swift",
            "Nested/Helper/Sources/H/Local.swift", "Package.swift", "Vendor/Loose/L.swift"
        ])
        #expect(FileClone.exists(copy.project.appendingPathComponent("Gen.swift")) == false)
    }

    @Test("files git checks out with other bytes (eol=crlf) are copied from the package and counted")
    func lineEndings() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            ".gitattributes": "*.swift eol=crlf\n",
            Self.library: WorkCopyHarness.swift,
            "Sources/Lib/B.swift": WorkCopyHarness.changed
        ])
        try repository.commit("one", day: 0)

        let (_, copy) = try WorkCopyHarness.copy(
            repository.root,
            scanning: [Self.library, "Sources/Lib/B.swift"],
            ignoring: []
        )

        #expect(copy.fixedFiles == 2)
        #expect(try WorkCopyHarness.text(Self.library, in: copy.project) == WorkCopyHarness.swift)
        #expect(try WorkCopyHarness.text("Sources/Lib/B.swift", in: copy.project) == WorkCopyHarness.changed)
        // A file the scan didn't parse keeps git's bytes.
        #expect(try WorkCopyHarness.text("Package.swift", in: copy.project).contains("\r\n"))
        #expect(try repository.git(["status", "--porcelain"]).isEmpty)
    }

    @Test("symbolic links, committed or untracked, are links in the copy and pass the hash check")
    func symbolicLinks() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/Real.swift": WorkCopyHarness.swift])
        let sources = repository.root.appendingPathComponent("Sources/Lib")
        try FileManager.default.createSymbolicLink(
            atPath: sources.appendingPathComponent("Link.swift").path,
            withDestinationPath: "Real.swift"
        )
        try repository.commit("one", day: 0)
        try FileManager.default.createSymbolicLink(
            atPath: sources.appendingPathComponent("Fresh.swift").path,
            withDestinationPath: "Real.swift"
        )

        let (_, copy) = try WorkCopyHarness.copy(
            repository.root,
            scanning: ["Sources/Lib/Real.swift", "Sources/Lib/Link.swift", "Sources/Lib/Fresh.swift"],
            ignoring: []
        )

        #expect(WorkCopyHarness.link("Sources/Lib/Link.swift", in: copy.project) == "Real.swift")
        #expect(WorkCopyHarness.link("Sources/Lib/Fresh.swift", in: copy.project) == "Real.swift")
        #expect(copy.fixedFiles == 0)
    }

    @Test("a store kept in the package, and SQLite's files beside it, are never copied")
    func storeInPackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([Self.library: WorkCopyHarness.swift])
        try repository.commit("one", day: 0)
        try repository.write(["Data/stats.sqlite": "db", "Data/stats.sqlite-wal": "wal", "Data/keep.txt": "keep\n"])

        let (_, copy) = try WorkCopyHarness.copy(
            repository.root,
            scanning: [Self.library],
            ignoring: ["Data/stats.sqlite"]
        )

        #expect(WorkCopyHarness.entries(of: copy.project) == ["Data/keep.txt", "Package.swift", Self.library])
    }
}
