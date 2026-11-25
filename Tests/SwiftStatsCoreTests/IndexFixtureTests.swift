//
//  IndexFixtureTests.swift
//  SwiftStatsCoreTests
//
//  The Index fixture's recordings (M7, design §13), made by
//  `Scripts/record-index-fixture.sh`: their shapes, their freshness against
//  the fixtures they were made from, and their placeholders.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The Index fixture's recordings (M7, design §13): each decodes with the
/// shape its readers expect, each is as fresh as the fixture it was made
/// from (so editing a fixture without re-recording fails here), and their
/// placeholders round-trip.
@Suite("Index fixture recordings")
struct IndexFixtureTests {
    /// The top-level keys of `index-check.py dump`'s JSON.
    private static let dumpKeys: Set<String> = ["root", "store", "library", "units", "records", "files"]
    /// The keys every outskirts 3.28.0 entry holds (design §5.3).
    private static let outskirtsKeys: Set<String> = [
        "accessibility", "attributes", "hints", "ids", "kind", "location", "modifiers", "modules", "name"
    ]
    /// Paths shaped as the recording script's: the root and IndexDep side by
    /// side in one folder, the scratch inside the root, the toolchain inside
    /// the developer folder.
    private static let paths = IndexFixture.Paths(
        root: "/fixture-run/work/Index",
        build: "/fixture-run/work/Index/.swiftstats/index-build",
        dependency: "/fixture-run/work/IndexDep",
        toolchain: "/fixture-run/Developer/Toolchains/Test.xctoolchain",
        temporary: "/fixture-run/temporary",
        developer: "/fixture-run/Developer"
    )
    /// Every placeholder.
    private static let placeholders = [
        IndexFixture.rootToken, IndexFixture.buildToken, IndexFixture.dependencyToken,
        IndexFixture.toolchainToken, IndexFixture.parentToken, IndexFixture.temporaryToken,
        IndexFixture.developerToken
    ]

    /// The recorded dumps: the fixture's two and the Diff fixture's two.
    private static func allDumps() throws -> [(name: String, data: Data)] {
        try IndexFixture.dumps.map { ($0, try IndexFixture.data($0)) }
            + ["before", "after"].map { ("Diff/\($0).json", try IndexFixture.diffDump($0)) }
    }

    /// The text of every recording, the Diff fixture's dumps included.
    private static func allTexts() throws -> [String] {
        try IndexFixture.recordings.map { try IndexFixture.text($0) }
            + ["before", "after"].map { try #require(String(bytes: try IndexFixture.diffDump($0), encoding: .utf8)) }
    }

    /// The JSON object in `data`.
    private static func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The hex SHA-256 of each Swift source and manifest of the package at
    /// `root`, by path in the package, leaving out `Recorded/` and build
    /// folders, with `edit` applied to a file's text first when it names it.
    private static func sourceHashes(
        of root: URL,
        edit: (String, String) -> String = { _, text in text }
    ) throws -> [String: String] {
        let manager = FileManager.default
        let entries = try #require(manager.enumerator(atPath: root.path))
        var hashes: [String: String] = [:]
        while let path = entries.nextObject() as? String {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if [".build", ".swiftstats", ".swiftpm"].contains(name) || path == "Recorded" {
                entries.skipDescendants()
                continue
            }
            guard path.hasSuffix(".swift"), entries.fileAttributes?[.type] as? FileAttributeType == .typeRegular else {
                continue
            }
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            let edited = edit(path, text)
            hashes[path] = edited == text
                ? ContentHash.sha256(try Data(contentsOf: root.appendingPathComponent(path)))
                : ContentHash.sha256(Data(edited.utf8))
        }
        return hashes
    }

    /// The recorded hash of each file of the dump in `data`, by path in the
    /// package.
    private static func recordedHashes(_ data: Data) throws -> [String: String] {
        let files = try JSONDecoder().decode(IndexFixture.DumpFiles.self, from: data).files
        var hashes: [String: String] = [:]
        for file in files {
            let prefix = IndexFixture.rootToken + "/"
            #expect(file.path.hasPrefix(prefix), "\(file.path) isn't under the root")
            hashes[String(file.path.dropFirst(prefix.count))] = file.sha256
        }
        return hashes
    }

    @Test("every dump holds the reader's keys and names its store and library by placeholder")
    func dumpShape() throws {
        for (name, data) in try Self.allDumps() {
            let dump = try Self.object(data)
            #expect(Set(dump.keys) == Self.dumpKeys, "\(name)")
            #expect(dump["root"] as? String == IndexFixture.rootToken, "\(name)")
            #expect(dump["store"] as? String == IndexFixture.buildToken + "/out", "\(name)")
            let library = try #require(dump["library"] as? [String: Any])
            #expect(library["path"] as? String == IndexFixture.toolchainToken + "/usr/lib/libIndexStore.dylib")
            #expect((dump["units"] as? [Any])?.isEmpty == false, "\(name)")
            #expect((dump["records"] as? [Any])?.isEmpty == false, "\(name)")
        }
    }

    @Test("every outskirts run is an array of entries holding the nine keys", arguments: IndexFixture.outskirtsRuns)
    func outskirtsShape(run: String) throws {
        let entries = try #require(try JSONSerialization.jsonObject(with: IndexFixture.data(run)) as? [[String: Any]])

        #expect(entries.isEmpty == false)
        for entry in entries {
            #expect(Self.outskirtsKeys.isSubset(of: entry.keys), "\(entry["name"] ?? "")")
        }
    }

    @Test("the describe decodes as the T1 describe, with its products and C99 names")
    func describeShape() throws {
        let data = try IndexFixture.data("describe.json")
        let package = try JSONDecoder().decode(DescribedPackage.self, from: data)
        let names = Dictionary(uniqueKeysWithValues: package.targets.map { ($0.name, $0.c99name) })

        #expect(try Self.object(data)["path"] as? String == IndexFixture.rootToken)
        #expect(package.name == "IndexFixture")
        #expect(names == [
            "IndexCore": "IndexCore", "index-kit": "index_kit", "index-support": "index_support",
            "IndexApp": "IndexApp", "IndexTool": "IndexTool", "IndexCoreTests": "IndexCoreTests",
            "IndexXCTests": "IndexXCTests"
        ])
        let libraries = package.products.filter { $0.kind == "library" }.map { "\($0.name): \($0.targets)" }
        #expect(libraries.sorted() == [#"IndexCore: ["IndexCore"]"#, #"IndexKit: ["index-kit"]"#])
    }

    @Test("the text recordings hold the toolchain, outskirts' version and the build's output")
    func textShape() throws {
        let toolchain = try IndexFixture.text("toolchain.txt").split(separator: "\n")
        let stderr = try IndexFixture.text("build.stderr")

        #expect(toolchain.count == 2)
        #expect(toolchain.first?.hasPrefix("toolchain: ") == true)
        #expect(toolchain.last == ".swift-version: absent")
        #expect(try IndexFixture.text("outskirts-version.txt") == "3.28.0\n")
        #expect(stderr.contains("ms\t\(IndexFixture.rootToken)/Sources/IndexCore/"))
        #expect(stderr.contains("macro expansion #expect:"))
        #expect(try IndexFixture.text("rebuild.stderr").contains("ms\t\(IndexFixture.rootToken)/"))
        #expect(try IndexFixture.text("failed.stderr").contains("error: Build failed"))
        #expect(try IndexFixture.text("build.stdout").isEmpty == false)
    }

    @Test("the recordings hold the cases later steps read: a borrowed subscript's _read, a global, a collision")
    func casesRecorded() throws {
        let stderr = try IndexFixture.text("build.stderr")
        let ring = IndexFixture.rootToken + "/Sources/IndexCore/Ring.swift"
        let reader = try IndexFixture.text("reader.json")

        // `_read` at the `subscript` keyword, the getter at its `{`, and the
        // global's initialiser timed as an expression outside every function.
        let subscriptName = "IndexCore.(file).Ring.subscript(_:)"
        #expect(stderr.contains("ms\t\(ring):25:12\t_read accessor \(subscriptName)._read accessor@"))
        #expect(stderr.contains("ms\t\(ring):25:44\tgetter \(subscriptName).getter@"))
        #expect(stderr.contains("ms\t\(ring):32:21\n"))
        // One key, `measure(_: Data)`, for two declarations with two USRs.
        #expect(reader.contains(#""usr":"s:9IndexCore7measureySi0A6DepKit4DataVF""#))
        #expect(reader.contains(#""usr":"s:9IndexCore7measureySi10Foundation4DataVF""#))
        // The Diff fixture's colliding pair, each in another file in `after`.
        for side in ["before", "after"] {
            let dump = try #require(String(bytes: try IndexFixture.diffDump(side), encoding: .utf8))
            #expect(dump.contains(#""usr":"s:8Spelling4size2ofSi10Foundation4DataV_tF""#), "\(side)")
            #expect(dump.contains(#""usr":"s:8Spelling4size2ofSi8Glossary4DataV_tF""#), "\(side)")
        }
    }

    @Test("the first build's dump hashes the Index fixture's files as they are")
    func readerFresh() throws {
        let recorded = try Self.recordedHashes(IndexFixture.data("reader.json"))
        let current = try Self.sourceHashes(of: IndexFixture.directory)

        #expect(recorded == current, "re-record with Scripts/record-index-fixture.sh")
    }

    @Test("the stale case's dump hashes the fixture's files after its rename and manifest edit")
    func staleReaderFresh() throws {
        let recorded = try Self.recordedHashes(IndexFixture.data("reader-stale.json"))
        var current = try Self.sourceHashes(of: IndexFixture.directory) { path, text in
            path == "Package.swift"
                ? IndexFixture.staleManifestEdits.reduce(text) { $0.replacingOccurrences(of: $1.old, with: $1.new) }
                : text
        }
        current[IndexFixture.staleRename.to] = current.removeValue(forKey: IndexFixture.staleRename.from)

        #expect(recorded == current, "re-record with Scripts/record-index-fixture.sh")
    }

    @Test("the Diff fixture's dumps hash its two trees as they are", arguments: ["before", "after"])
    func diffFresh(side: String) throws {
        let recorded = try Self.recordedHashes(IndexFixture.diffDump(side))
        let current = try Self.sourceHashes(of: IndexFixture.diffDirectory.appendingPathComponent(side))

        #expect(recorded == current, "re-record with Scripts/record-index-fixture.sh")
    }

    @Test("IndexDep's files are as recorded")
    func dependencyFresh() throws {
        var recorded: [String: String] = [:]
        for line in try IndexFixture.text("dependency-files.txt").split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            recorded[parts.last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""] = parts.first.map(String.init)
        }
        let current = try Self.sourceHashes(of: IndexFixture.dependencyDirectory)

        #expect(recorded == current, "re-record with Scripts/record-index-fixture.sh")
    }

    @Test("every file the outskirts runs name exists in the fixtures", arguments: IndexFixture.outskirtsRuns)
    func outskirtsPathsExist(run: String) throws {
        let entries = try #require(try JSONSerialization.jsonObject(with: IndexFixture.data(run)) as? [[String: Any]])
        let folders = [
            IndexFixture.rootToken: IndexFixture.directory,
            IndexFixture.dependencyToken: IndexFixture.dependencyDirectory
        ]

        for entry in entries {
            let location = try #require(entry["location"] as? String)
            let parts = location.split(separator: "/", maxSplits: 1).map(String.init)
            let folder = try #require(folders[parts[0]], "\(location) is under neither placeholder")
            var path = String(try #require(parts.last?.split(separator: ":").first))
            if run.contains("stale"), path == IndexFixture.staleRename.to {
                path = IndexFixture.staleRename.from
            }
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path), "\(location)")
        }
    }

    @Test("restoring a run's paths and redacting them again gives every recording back")
    func placeholdersRoundTrip() throws {
        for text in try Self.allTexts() {
            let restored = IndexFixture.restore(text, paths: Self.paths)
            #expect(Self.placeholders.allSatisfy { restored.contains($0) == false })
            #expect(IndexFixture.redact(restored, paths: Self.paths) == text)
        }
        let dump = try IndexFixture.text("reader.json", restoring: Self.paths)
        #expect(dump.contains("\"root\":\"/fixture-run/work/Index\""))
        #expect(dump.contains("/fixture-run/work/IndexDep/Sources/IndexDepKit/DepKit.swift"))
        #expect(dump.contains("/fixture-run/work/Index/.swiftstats/index-build/out/Intermediates.noindex"))
        let stderr = try IndexFixture.text("build.stderr", restoring: Self.paths)
        #expect(stderr.contains("/fixture-run/Developer/Toolchains/Test.xctoolchain/usr/bin/swift-frontend"))
        #expect(stderr.contains("/fixture-run/Developer/Platforms/MacOSX.platform/Developer/SDKs/"))
    }

    @Test("no recording names this machine's paths")
    func nothingPrivate() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let machinePaths = ["/Users/", "/private/", "/var/folders/", "/Applications/", home]

        for text in try Self.allTexts() {
            #expect(machinePaths.allSatisfy { text.contains($0) == false })
        }
    }
}
