//
//  IndexStoreReaderTests.swift
//  SwiftStatsCoreTests
//
//  `IndexStoreReader` without a store (M7, design §2.1–§2.2): the pin
//  `Package.resolved` records, the one file importing `IndexStore`, the
//  real paths it gives, the code point order of its names, a library that
//  doesn't load, and the scanner's `indexSource` factory, the product's
//  reader unless a test replaces it, kept by a workspace's backfill.
//  No libIndexStore is loaded here; `IndexStoreReaderLiveTests` reads a
//  real store when asked to.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The index store reader's pin, paths and factory.
@Suite("Index store reader")
struct IndexStoreReaderTests {
    /// The SwiftStats checkout these tests were built from.
    private static let checkout = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// A line importing indexstore-db's `IndexStore` or `IndexStoreDB`
    /// module, or a declaration from one: any attributes (`@_spi(…)`
    /// included), access level and declaration kind, then the module name
    /// followed by anything but more of a name (`.Member`, `;`, a comment).
    private static let importLine = try? NSRegularExpression(
        pattern: #"^\s*(@\w+(\([^)]*\))?\s+)*((public|package|internal|fileprivate|private)\s+)?"#
            + #"import\s+((typealias|struct|class|enum|protocol|let|var|func)\s+)?"#
            + #"(IndexStore|IndexStoreDB)\b"#,
        options: [.anchorsMatchLines]
    )
    /// The capture group of `importLine` that holds the module's name.
    private static let moduleGroup = 7

    /// The real path of `url` (realpath(3)).
    private static func realPath(_ url: URL) throws -> String {
        let resolved = try #require(realpath(url.path, nil))
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The module each line of `text` imports from `IndexStore` or
    /// `IndexStoreDB`, in order.
    private static func importedModules(in text: String) throws -> [String] {
        let expression = try #require(importLine)
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: moduleGroup), in: text).map { String(text[$0]) }
        }
    }

    /// Each Swift file under `Sources/` or `Tests/` that imports
    /// `IndexStore` or `IndexStoreDB`, relative to the checkout, with the
    /// modules it imports. Fixture packages are left out: they are built
    /// apart and never link indexstore-db.
    private static func importers() throws -> [String: [String]] {
        var found: [String: [String]] = [:]
        for top in ["Sources", "Tests"] {
            let directory = checkout.appendingPathComponent(top)
            let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            for path in paths.sorted() where path.hasSuffix(".swift") && path.hasPrefix("Fixtures/") == false {
                let text = try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
                let modules = try importedModules(in: text)
                if modules.isEmpty == false {
                    found[top + "/" + path] = modules
                }
            }
        }
        return found
    }

    @Test("the pinned revision is indexstore-db's in Package.resolved, and the identity and version name it")
    func pin() throws {
        let lockfile = try #require(PackageResolvedReader.lockfile(root: Self.checkout).lockfile)
        let pin = try #require(lockfile.pins.first { $0.identity == "indexstore-db" })
        let lmdb = try #require(lockfile.pins.first { $0.identity == "swift-lmdb" })

        #expect(pin.revision == IndexStoreReader.pinned)
        #expect(pin.version == nil)
        #expect(pin.location == "https://github.com/swiftlang/indexstore-db.git")
        #expect(IndexStoreReader.identity == "git:" + IndexStoreReader.pinned)
        #expect(IndexStoreReader.version == "indexstore-db swift-6.4.2-RELEASE")
        // Resolved by branch, never compiled: only the IndexStore product is linked.
        #expect(lmdb.branch == "release/6.4.x")
    }

    @Test("only the reader imports IndexStore, nothing imports IndexStoreDB, and only the IndexStore product is linked")
    func onlyImporter() throws {
        let manifest = try String(contentsOf: Self.checkout.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(try Self.importers() == ["Sources/SwiftStatsCore/Index/IndexStoreReader.swift": ["IndexStore"]])
        #expect(manifest.contains(#".product(name: "IndexStore", package: "indexstore-db")"#))
        #expect(manifest.contains(#".product(name: "IndexStoreDB""#) == false)
    }

    @Test("the import check sees attributed, declaration-kind, member and commented imports, and no other module")
    func importSpellings() throws {
        let seen = [
            "import IndexStore",
            "import IndexStoreDB // why",
            "import IndexStore;",
            "  @_implementationOnly import IndexStore",
            "@preconcurrency import class IndexStoreDB.IndexStoreDB",
            "import struct IndexStore.IndexStoreUnit",
            "@_spi(Testing) public import IndexStoreDB",
            "package import func IndexStore.something"
        ]
        let unseen = [
            "import IndexStoreReader",
            "import IndexStoreCAPIExtras",
            "// import IndexStore",
            "let note = \"import IndexStore\"",
            "import Foundation"
        ]

        for line in seen {
            #expect(try Self.importedModules(in: line).count == 1, "\(line)")
        }
        for line in unseen {
            #expect(try Self.importedModules(in: line).isEmpty, "\(line)")
        }
        #expect(try Self.importedModules(in: seen.joined(separator: "\n")) == [
            "IndexStore", "IndexStoreDB", "IndexStore", "IndexStore", "IndexStoreDB", "IndexStore", "IndexStoreDB",
            "IndexStore"
        ])
    }

    @Test("""
        unit and record names sort in code point order, a decomposed name before a later-composed one, \
        in the reader and in recordings
        """)
    func codePointOrder() {
        let decomposed = "Cafe\u{301}.swift.o-A"
        let plain = "Caff.swift.o-B"
        let modified = IndexUnitFact.ModificationDate(seconds: 1, nanoseconds: 0)
        let units = [plain, decomposed].map { name in
            IndexUnitFact(
                name: name,
                module: "Kit",
                mainFile: "",
                target: "arm64-apple-macosx14.0",
                isSystem: false,
                modified: modified,
                records: [],
                moduleDependencies: []
            )
        }

        // `String`'s own order compares NFC forms, where `é` follows `f`.
        #expect([decomposed, plain].sorted() == [plain, decomposed])
        #expect(IndexStoreReader.codePointSorted([plain, decomposed]) == [decomposed, plain])
        #expect(IndexStoreReader.codePointPrecedes(decomposed, plain))
        #expect(IndexStoreReader.codePointSorted(["b", "a", "b"]) == ["a", "b", "b"])
        #expect(RecordedIndexSource(units: units, records: []).unitNames() == [decomposed, plain])
    }

    @Test("""
        paths are made real paths in NFC, a missing tail kept after its longest existing ancestor, \
        a relative path only normalized
        """)
    func realPaths() throws {
        let top = FileManager.default.temporaryDirectory.appendingPathComponent("IndexStoreReader-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: top) }
        let real = top.appendingPathComponent("real")
        try FileManager.default.createDirectory(
            at: real.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try Data().write(to: real.appendingPathComponent("Sources/Kit.swift"))
        let link = top.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let realTop = try Self.realPath(real)

        #expect(IndexStoreReader.realPath(link.path + "/Sources/Kit.swift") == realTop + "/Sources/Kit.swift")
        #expect(IndexStoreReader.realPath(link.path + "/Sources/") == realTop + "/Sources")
        #expect(IndexStoreReader.realPath(link.path + "/Gone/Moved.swift") == realTop + "/Gone/Moved.swift")
        #expect(IndexStoreReader.realPath(link.path + "/Cafe\u{301}.swift") == realTop + "/Caf\u{E9}.swift")
        #expect(IndexStoreReader.realPath(link.path + "/Cafe\u{301}.swift").unicodeScalars.contains("\u{301}") == false)
        #expect(IndexStoreReader.realPath("/") == "/")
        #expect(IndexStoreReader.realPath("Sources/Cafe\u{301}.swift") == "Sources/Caf\u{E9}.swift")
    }

    @Test("the scanner's default factory is the reader, which fails naming a library that doesn't load")
    func defaultFactory() async throws {
        let top = FileManager.default.temporaryDirectory.appendingPathComponent("IndexStoreReader-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: top) }
        try FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
        let library = top.appendingPathComponent("libIndexStore.dylib")
        try Data("not a library\n".utf8).write(to: library)
        let open = PackageScanner().indexSource
        // The reader's library load goes through `BlockingAsync`, so it runs
        // on a thread of its own.
        let run = ThreadRun { () -> String? in
            do {
                _ = try open(top, library)
                return nil
            } catch {
                return (error as? IndexStoreReader.Failure)?.description
            }
        }

        let reason = try #require(await run.value)
        #expect(reason.hasPrefix("libIndexStore.dylib didn't load: "))
        #expect(reason.contains(library.path))
    }

    @Test("a test's factory replaces the reader and is given the store and library")
    func replacedFactory() throws {
        let store = URL(fileURLWithPath: "/run/work/Index/.swiftstats/index-build/out")
        let library = URL(fileURLWithPath: "/run/toolchain/usr/lib/libIndexStore.dylib")
        let recording = try IndexFixture.data("reader.json")
        let scanner = PackageScanner().readingIndex { givenStore, givenLibrary in
            guard givenStore == store, givenLibrary == library else {
                throw IndexStoreReader.Failure(description: "given \(givenStore.path) and \(givenLibrary.path)")
            }
            return try RecordedIndexSource(recording: recording, restoring: [:])
        }

        let source = try scanner.indexSource(store, library)
        #expect(try source.unitNames().count == 26)
        #expect(source is RecordedIndexSource)
    }

    @Test("a workspace's factory reaches its scans and backfill's, with or without the tools")
    func threadedFactory() async throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Package.swift": "// swift-tools-version: 6.0\n"])
        let store = URL(fileURLWithPath: "/run/work/Index/.swiftstats/index-build/out")
        let library = URL(fileURLWithPath: "/run/toolchain/usr/lib/libIndexStore.dylib")
        let recording = try IndexFixture.data("reader.json")
        let workspace = try repository.workspace().readingIndex { _, _ in
            try RecordedIndexSource(recording: recording, restoring: [:])
        }
        let scanners = [
            workspace.scanner.scanner,
            workspace.backfillScanner(withTools: false).scanner,
            workspace.backfillScanner(withTools: true).scanner
        ]

        let factories = scanners.map(\.indexSource)
        // Were the product's reader reached, its library load would go
        // through `BlockingAsync`, so the factories run on a thread of
        // their own.
        let run = ThreadRun {
            factories.map { factory in (try? factory(store, library)) is RecordedIndexSource }
        }

        #expect(await run.value == [true, true, true])
        #expect(scanners.map(\.toolSkipReason) == [nil, SnapshotWorkspace.backfillToolSkipReason, nil])
    }
}
