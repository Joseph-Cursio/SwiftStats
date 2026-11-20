//
//  DiffHunkTests.swift
//  SwiftStatsCoreTests
//
//  The diff hunks divergent clones reads (PRD §8): the old side of each
//  hunk of a zero-context diff, by the earlier path, and when a hunk lies
//  in a copy's lines.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Diff hunks")
struct DiffHunkTests {
    /// Commits ten lines to `File.swift` in `repository`, then a change to
    /// line 5, and returns both commits.
    static func commitLineFive(in repository: HistoryRepository) throws -> (first: String, second: String) {
        let lines = (1...10).map { "let value\($0) = \($0)" }
        try repository.write(["File.swift": lines.joined(separator: "\n") + "\n"])
        let first = try repository.commit("Ten lines", day: 0)
        var changed = lines
        changed[4] = "let value5 = 50"
        try repository.write(["File.swift": changed.joined(separator: "\n") + "\n"])
        return (first, try repository.commit("Change line five", day: 1))
    }

    @Test("hunks are read by old path in the package, following renames, past content that looks like a header")
    func parsing() {
        let diff = """
        diff --git a/Pkg/Sources/A.swift b/Pkg/Sources/A.swift
        index 1111111..2222222 100644
        --- a/Pkg/Sources/A.swift
        +++ b/Pkg/Sources/A.swift
        @@ -3,2 +3,1 @@ func alpha() {
        -    let old = 1
        --- a/Pkg/Sources/Fake.swift
        +    let new = 2
        @@ -10,0 +10,3 @@
        +    added()
        diff --git a/Pkg/Sources/Old.swift b/Pkg/Sources/New.swift
        similarity index 90%
        rename from Pkg/Sources/Old.swift
        rename to Pkg/Sources/New.swift
        --- a/Pkg/Sources/Old.swift
        +++ b/Pkg/Sources/New.swift
        @@ -7 +7 @@
        diff --git a/Pkg/Sources/Fresh.swift b/Pkg/Sources/Fresh.swift
        new file mode 100644
        --- /dev/null
        +++ b/Pkg/Sources/Fresh.swift
        @@ -0,0 +1,2 @@
        diff --git a/Elsewhere/X.swift b/Elsewhere/X.swift
        --- a/Elsewhere/X.swift
        +++ b/Elsewhere/X.swift
        @@ -1 +1 @@
        diff --git "a/Pkg/Sources/Tab\\there.swift" "b/Pkg/Sources/Tab\\there.swift"
        --- "a/Pkg/Sources/Tab\\there.swift"
        +++ "b/Pkg/Sources/Tab\\there.swift"
        @@ -4,2 +4,0 @@
        diff --git "a/Pkg/Sources/Caf\\303\\251.swift" "b/Pkg/Sources/Caf\\303\\251.swift"
        --- "a/Pkg/Sources/Caf\\303\\251.swift"
        @@ -2,1 +2,1 @@

        """

        let hunks = GitChanges.hunks(inDiff: diff, packagePath: "Pkg")

        #expect(hunks == [
            "Sources/A.swift": [DiffHunk(start: 3, count: 2), DiffHunk(start: 10, count: 0)],
            "Sources/Old.swift": [DiffHunk(start: 7, count: 1)],
            "Sources/Tab\there.swift": [DiffHunk(start: 4, count: 2)],
            "Sources/Café.swift": [DiffHunk(start: 2, count: 1)]
        ])
        #expect(GitChanges.hunks(inDiff: diff, packagePath: "")["Elsewhere/X.swift"] == [DiffHunk(start: 1, count: 1)])
    }

    @Test("a changed line that isn't UTF-8 leaves the UTF-8 paths of other files readable")
    func mixedEncodings() {
        var data = Data("""
        diff --git a/Pkg/Fixtures/legacy.txt b/Pkg/Fixtures/legacy.txt
        --- a/Pkg/Fixtures/legacy.txt
        +++ b/Pkg/Fixtures/legacy.txt
        @@ -1 +1 @@
        -caf
        """.utf8)
        // "café" in ISO-8859-1: not valid UTF-8.
        data.append(contentsOf: [0xE9, UInt8(ascii: "\n")])
        data.append(contentsOf: Data("""
        +cafe
        diff --git a/Pkg/Sources/Café.swift b/Pkg/Sources/Café.swift
        --- a/Pkg/Sources/Café.swift
        +++ b/Pkg/Sources/Café.swift
        @@ -5,2 +5,2 @@

        """.utf8))

        let text = GitChanges.text(of: data)
        let hunks = GitChanges.hunks(inDiff: text, packagePath: "Pkg")

        #expect(hunks["Sources/Café.swift"] == [DiffHunk(start: 5, count: 2)])
        #expect(hunks["Fixtures/legacy.txt"] == [DiffHunk(start: 1, count: 1)])
        #expect(text.contains("-café\n"))
    }

    @Test("a replacement overlaps the lines it meets; an insertion only lines it falls inside")
    func overlapping() {
        let replacement = DiffHunk(start: 3, count: 2)
        let insertion = DiffHunk(start: 5, count: 0)

        #expect(replacement.overlaps(lower: 4, upper: 9))
        #expect(replacement.overlaps(lower: 1, upper: 3))
        #expect(replacement.overlaps(lower: 5, upper: 9) == false)
        #expect(replacement.overlaps(lower: 1, upper: 2) == false)
        // Inserting after line 5 is inside 5–9, and after the end of 1–5.
        #expect(insertion.overlaps(lower: 5, upper: 9))
        #expect(insertion.overlaps(lower: 1, upper: 5) == false)
        #expect(insertion.overlaps(lower: 6, upper: 9) == false)
    }

    @Test("an exported GIT_DIFF_OPTS doesn't give the zero-context diff context lines")
    func diffOptionsPinned() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let (first, second) = try Self.commitLineFive(in: repository)

        let plain = try GitChanges.hunks(from: first, to: second, packagePath: "", in: repository.root)
        let exported = try GitChanges.hunks(
            from: first,
            to: second,
            packagePath: "",
            in: repository.root,
            inherited: ["GIT_DIFF_OPTS": "-u3"]
        )

        #expect(plain["File.swift"] == [DiffHunk(start: 5, count: 1)])
        // With three lines of context git would report lines 2–8.
        #expect(exported["File.swift"] == [DiffHunk(start: 5, count: 1)])
    }

    @Test("a -diff attribute or core.bigFileThreshold doesn't turn a file's hunks into a binary notice")
    func diffedAsText() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let (first, second) = try Self.commitLineFive(in: repository)
        let attributes = repository.root.appendingPathComponent(".git/info/attributes")
        try FileManager.default.createDirectory(
            at: attributes.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try "*.swift -diff\n".write(to: attributes, atomically: true, encoding: .utf8)
        let attributed = try GitChanges.hunks(from: first, to: second, packagePath: "", in: repository.root)
        try FileManager.default.removeItem(at: attributes)
        try repository.git(["config", "core.bigFileThreshold", "10"])
        let big = try GitChanges.hunks(from: first, to: second, packagePath: "", in: repository.root)

        #expect(attributed["File.swift"] == [DiffHunk(start: 5, count: 1)])
        #expect(big["File.swift"] == [DiffHunk(start: 5, count: 1)])
    }

    @Test("only the package's Swift files are diffed, so a changed binary asset adds nothing to the diff")
    func swiftFilesOnly() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let asset = repository.root.appendingPathComponent("Pkg/Resources/asset.bin")
        try repository.write(["Pkg/Top.swift": "let top = 1\n", "Pkg/Sources/Kit/Deep.swift": "let deep = 1\n"])
        try repository.write(["Pkg/notes.md": "one\n", "Elsewhere.swift": "let other = 1\n"])
        try FileManager.default.createDirectory(
            at: asset.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0, 1, 2, 0xFF, 10, 0]).write(to: asset)
        let first = try repository.commit("Files", day: 0)
        try repository.write(["Pkg/Top.swift": "let top = 2\n", "Pkg/Sources/Kit/Deep.swift": "let deep = 2\n"])
        try repository.write(["Pkg/notes.md": "two\n", "Elsewhere.swift": "let other = 2\n"])
        try Data([0, 3, 4, 0xFE, 10, 0]).write(to: asset)
        let second = try repository.commit("Change them all", day: 1)

        let hunks = try GitChanges.hunks(
            from: first,
            to: second,
            packagePath: "Pkg",
            in: repository.root.appendingPathComponent("Pkg")
        )

        #expect(Set(hunks.keys) == ["Top.swift", "Sources/Kit/Deep.swift"])
    }

    @Test("an exported GIT_LITERAL_PATHSPECS doesn't stop the diff naming the Swift files")
    func literalPathspecsPinned() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let (first, second) = try Self.commitLineFive(in: repository)

        let exported = try GitChanges.hunks(
            from: first,
            to: second,
            packagePath: "",
            in: repository.root,
            inherited: ["GIT_LITERAL_PATHSPECS": "1"]
        )

        #expect(exported["File.swift"] == [DiffHunk(start: 5, count: 1)])
    }
}
