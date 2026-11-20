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
}
