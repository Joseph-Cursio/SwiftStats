import Foundation
@testable import SwiftStatsCore
import Testing

/// What the copy `swift-infer` runs in holds when the package names its
/// own vocabulary or has files the measure step can't read, and how a
/// failure to make the copy is reported (PRD §7.11).
@Suite("SwiftInferProperties copy")
struct SwiftInferCopyTests {
    /// The vocabulary a config can name.
    private static let vocabulary = "{\"idempotenceVerbs\": [\"frobnicate\"]}\n"

    /// A fake indexer writing an empty index for every indexed target.
    private static func indexer() throws -> URL {
        let empty = PropertyHarness.emptyIndex
        return try FakeTool.makeIndexer(
            indexes: ["Core": empty, "Macros": empty, "Tool": empty],
            errors: [:],
            statuses: [:],
            delays: [:]
        )
    }

    /// The harness package with a config naming `path` as its vocabulary.
    private static func package(vocabularyPath path: String, files: [String: String]) throws -> TemporaryPackage {
        let config = "[discover]\nvocabularyPath = \"\(path)\"\n"
        return try PropertyHarness.package(files.merging([".swiftinfer/config.toml": config]) { given, _ in given })
    }

    @Test("a vocabulary the config names inside the package is copied to its path and hashed in the options")
    func configuredVocabularyInside() throws {
        let package = try Self.package(vocabularyPath: "vocab/terms.json", files: ["vocab/terms.json": Self.vocabulary])
        defer { package.remove() }
        let tool = try Self.indexer()
        defer { PropertyHarness.remove(tool) }

        let report = try package.scan(tools: PropertyHarness.locator(tool))

        #expect(PropertyHarness.status(report)?.state == .ran)
        #expect(FakeTool.log("files-Core.txt", of: tool).contains("./vocab/terms.json"))
        let options = PropertyHarness.status(report)?.options ?? []
        let hash = ContentHash.sha256(Data(Self.vocabulary.utf8))
        #expect(options.contains("vocabulary.json: vocab/terms.json sha256:\(hash)"))
        #expect(options.contains("vocabulary.json: absent") == false)
        #expect(FakeTool.arguments(of: tool).sorted() == [
            "index --target Core", "index --target Macros", "index --target Tool"
        ])
    }

    @Test("""
        a vocabulary named by an absolute path is read where it is and hashed; one named by a relative path \
        leaving the package is passed with --vocabulary; a missing one is absent
        """)
    func configuredVocabularyOutside() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vocabulary-\(UUID().uuidString).json")
        try Data(Self.vocabulary.utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let hash = ContentHash.sha256(Data(Self.vocabulary.utf8))
        let absolute = try Self.package(vocabularyPath: outside.path, files: [:])
        defer { absolute.remove() }
        let relative = "../\(outside.lastPathComponent)"
        let leaving = try Self.package(vocabularyPath: relative, files: [:])
        defer { leaving.remove() }
        let missing = try Self.package(vocabularyPath: "vocab/missing.json", files: [
            ".swiftinfer/vocabulary.json": Self.vocabulary
        ])
        defer { missing.remove() }
        let absoluteTool = try Self.indexer()
        defer { PropertyHarness.remove(absoluteTool) }
        let leavingTool = try Self.indexer()
        defer { PropertyHarness.remove(leavingTool) }
        let missingTool = try Self.indexer()
        defer { PropertyHarness.remove(missingTool) }

        let absoluteReport = try absolute.scan(tools: PropertyHarness.locator(absoluteTool))
        let leavingReport = try leaving.scan(tools: PropertyHarness.locator(leavingTool))
        let missingReport = try missing.scan(tools: PropertyHarness.locator(missingTool))

        #expect(PropertyHarness.status(absoluteReport)?.options.contains(
            "vocabulary.json: \(outside.path) sha256:\(hash)"
        ) == true)
        #expect(FakeTool.arguments(of: absoluteTool).contains("index --target Core"))
        #expect(PropertyHarness.status(leavingReport)?.options.contains(
            "vocabulary.json: \(relative) sha256:\(hash)"
        ) == true)
        let named = leaving.root.appendingPathComponent(relative).path
        #expect(FakeTool.arguments(of: leavingTool).contains("index --target Core --vocabulary \(named)"))
        #expect(PropertyHarness.status(missingReport)?.options.contains(
            "vocabulary.json: vocab/missing.json absent"
        ) == true)
        // The tool reads no vocabulary then, not the conventional one.
        #expect(FakeTool.log("files-Core.txt", of: missingTool).contains("./.swiftinfer/vocabulary.json") == false)
    }

    @Test("vocabularyPath is read as swift-infer reads it: in [discover], a basic string, comments outside strings")
    func configuredPathReading() {
        let read = SwiftInferVocabulary.configuredPath(in:)
        #expect(read("[discover]\nvocabularyPath = \"a#b.json\" # note\n") == "a#b.json")
        #expect(read("[discover]\n  vocabularyPath=\"say \\\"hi\\\"\\\\x.json\"\n") == "say \"hi\"\\x.json")
        #expect(read("vocabularyPath = \"root.json\"\n[other]\nvocabularyPath = \"other.json\"\n") == nil)
        #expect(read("[discover]\n# vocabularyPath = \"commented.json\"\nincludePossible = true\n") == nil)
        #expect(read("[discover]\nvocabularyPath = true\n") == nil)
        #expect(read("[discover]\nvocabularyPath = \"bad \\q escape\"\n") == nil)
        // A file the tool can't parse, anywhere, is ignored as a whole.
        let named = "[discover]\nvocabularyPath = \"vocab/terms.json\"\n"
        #expect(read(named + "[other]\nflag = false # fine\n\n") == "vocab/terms.json")
        for rejected in [
            "maxSuggestions = 10\n", "packs = [\"a\"]\n", "packs = 'literal'\n", "a.b = true\n",
            "bad key = true\n", "includePossible = true\nincludePossible = false\n", "[discover]\n",
            "[other\n", "[]\n", "loose line\n"
        ] {
            #expect(read(named + rejected) == nil, "\(rejected)")
        }
    }

    @Test("""
        a config swift-infer can't parse names no vocabulary: the conventional file is copied and hashed, \
        not the file the config names
        """)
    func unparsableConfig() throws {
        let conventional = "{\"idempotenceVerbs\": [\"normalize\"]}\n"
        let config = "[discover]\nvocabularyPath = \"vocab/terms.json\"\nmaxSuggestions = 10\n"
        let package = try PropertyHarness.package([
            ".swiftinfer/config.toml": config,
            ".swiftinfer/vocabulary.json": conventional,
            "vocab/terms.json": Self.vocabulary
        ])
        defer { package.remove() }
        let tool = try Self.indexer()
        defer { PropertyHarness.remove(tool) }

        let report = try package.scan(tools: PropertyHarness.locator(tool))

        #expect(PropertyHarness.status(report)?.state == .ran)
        let copied = FakeTool.log("files-Core.txt", of: tool)
        #expect(copied.contains("./.swiftinfer/vocabulary.json"))
        #expect(copied.contains("./vocab/terms.json") == false)
        let hash = ContentHash.sha256(Data(conventional.utf8))
        #expect(PropertyHarness.status(report)?.options.contains("vocabulary.json: sha256:\(hash)") == true)
    }

    @Test("""
        a target file the measure step skips, unreadable or not UTF-8, is left out of the copy too, and the \
        collector still runs, the same way twice
        """)
    func unreadableTargetFiles() throws {
        var targets = PropertyHarness.targets
        targets[0] = PropertyHarness.target("Core", "library", "Sources/Core", [
            "Latin.swift", "Locked.swift", "Values.swift"
        ])
        let package = try TemporaryPackage(PropertyHarness.files.merging([
            "Sources/Core/Locked.swift": "public func locked() -> Int { 1 }\n"
        ]) { _, new in new }, targets: targets)
        defer { package.remove() }
        try Data([0x2F, 0x2F, 0xE9, 0x0A]).write(to: package.root.appendingPathComponent("Sources/Core/Latin.swift"))
        let locked = package.root.appendingPathComponent("Sources/Core/Locked.swift").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked) }
        let tool = try Self.indexer()
        defer { PropertyHarness.remove(tool) }

        let first = try package.scan(tools: PropertyHarness.locator(tool))
        let second = try package.scan(tools: PropertyHarness.locator(tool))

        #expect(PropertyHarness.status(first)?.state == .ran)
        let copied = FakeTool.log("files-Core.txt", of: tool)
        #expect(copied.contains("./Sources/Core/Values.swift"))
        #expect(copied.contains("./Sources/Core/Locked.swift") == false)
        #expect(copied.contains("./Sources/Core/Latin.swift") == false)
        #expect(first.warnings.compactMap(\.file).sorted() == ["Sources/Core/Latin.swift", "Sources/Core/Locked.swift"])
        #expect(try ScanReportEncoder.encode(first) == ScanReportEncoder.encode(second))
    }

    @Test("a copy that can't be made fails with the same reason twice, naming no path in the package or address")
    func copyFailureReason() throws {
        let package = try PropertyHarness.package([:])
        defer { package.remove() }
        let manifest = package.root.appendingPathComponent("Package.swift").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: manifest)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: manifest) }
        let tool = try Self.indexer()
        defer { PropertyHarness.remove(tool) }

        let first = try package.scan(tools: PropertyHarness.locator(tool))
        let second = try package.scan(tools: PropertyHarness.locator(tool))

        #expect(PropertyHarness.status(first)?.state == .failed)
        let reason = try #require(PropertyHarness.status(first)?.reason)
        #expect(reason == PropertyHarness.status(second)?.reason)
        #expect(reason.contains("Package.swift"))
        #expect(PathSpellings.of(package.root).allSatisfy { reason.contains($0) == false })
        #expect(reason.contains("0x") == false)
    }
}
