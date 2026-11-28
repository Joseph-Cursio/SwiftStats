import Foundation
@testable import SwiftStatsCore
import Testing

/// The old paths diff hunks are filed under, as git writes them: a path
/// git quotes reads back through every escape git writes, its letter
/// escapes `\a \b \t \n \v \f \r \" \\` and octal ones (design B34); and a
/// path lies in the package by its components, the `/`s found among
/// Unicode scalars, so one whose first component below the package starts
/// with a combining mark, which joins the `/` before it into one
/// Character, is still in it (design B35, decided U13), while a package
/// path spelled in the other normalization form still matches, as Swift
/// strings compare; the package folder itself is not in it.
extension DiffHunkTests {
    @Test(
        """
        a path git quotes reads back through each escape git writes, letters and octal, so its hunks are filed \
        under the name git escaped (design B34)
        """,
        arguments: [
            ("x\\ay", "x\u{7}y"),
            ("x\\by", "x\u{8}y"),
            ("x\\ty", "x\ty"),
            ("x\\ny", "x\ny"),
            ("x\\vy", "x\u{B}y"),
            ("x\\fy", "x\u{C}y"),
            ("x\\ry", "x\ry"),
            ("x\\\"y", "x\"y"),
            ("x\\\\y", "x\\y"),
            ("x\\001y", "x\u{1}y"),
            ("x\\177y", "x\u{7F}y"),
            ("Caf\\303\\251", "Caf\u{E9}")
        ]
    )
    func quotedPaths(escaped: String, name: String) {
        // As git writes them (core.quotepath off): quoted, with C escapes.
        let diff = """
        diff --git "a/Pkg/\(escaped).swift" "b/Pkg/\(escaped).swift"
        index 7898192..f5f1a5f 100644
        --- "a/Pkg/\(escaped).swift"
        +++ "b/Pkg/\(escaped).swift"
        @@ -2 +2 @@
        -b
        +c

        """

        let hunks = GitChanges.hunks(inDiff: diff, packagePath: "Pkg")

        #expect(hunks == ["\(name).swift": [DiffHunk(start: 2, count: 1)]])
        #expect(hunks.keys.map { Array($0.unicodeScalars) } == [Array("\(name).swift".unicodeScalars)])
    }

    @Test(
        """
        a path whose first component below the package starts with a combining mark, a joiner, a variation \
        selector or a spacing mark is in the package, and so is every path at the top when the package is the \
        repository (design B35, decided U13)
        """,
        arguments: ["\u{301}", "\u{200D}", "\u{FE0F}", "\u{903}"]
    )
    func markAfterSlash(mark: String) {
        let diff = { (folder: String) in
            """
            diff --git a/\(folder)\(mark)z.swift b/\(folder)\(mark)z.swift
            --- a/\(folder)\(mark)z.swift
            +++ b/\(folder)\(mark)z.swift
            @@ -3,2 +3 @@
            diff --git a/\(folder)Sources/\(mark)w.swift b/\(folder)Sources/\(mark)w.swift
            --- a/\(folder)Sources/\(mark)w.swift
            +++ b/\(folder)Sources/\(mark)w.swift
            @@ -7 +7 @@

            """
        }

        let inPackage = GitChanges.hunks(inDiff: diff("Pkg/"), packagePath: "Pkg")
        let atTop = GitChanges.hunks(inDiff: diff(""), packagePath: "")

        #expect(inPackage == [
            "\(mark)z.swift": [DiffHunk(start: 3, count: 2)],
            "Sources/\(mark)w.swift": [DiffHunk(start: 7, count: 1)]
        ])
        #expect(atTop == inPackage)
        #expect(Set(inPackage.keys.map { Array($0.unicodeScalars).first }) == ["S", mark.unicodeScalars.first])
    }

    @Test(
        """
        a file whose old path is the package folder itself, a file there in the older commit, lies outside the \
        package, so its hunks are dropped, not filed under an empty path
        """,
        arguments: ["Pkg", "Sub/Pkg.swift"]
    )
    func packageFolderItself(package: String) {
        let diff = """
        diff --git a/\(package) b/\(package)
        deleted file mode 100644
        index 7898192..0000000
        --- a/\(package)
        +++ /dev/null
        @@ -1 +0,0 @@
        diff --git a/\(package)/x.swift b/\(package)/x.swift
        --- a/\(package)/x.swift
        +++ b/\(package)/x.swift
        @@ -6 +6 @@

        """

        #expect(GitChanges.hunks(inDiff: diff, packagePath: package) == ["x.swift": [DiffHunk(start: 6, count: 1)]])
    }

    @Test("a package path spelled in the other normalization form than git's paths still holds them")
    func packageNormalization() {
        let decomposed = "Cafe\u{301}"
        let diff = """
        diff --git a/\(decomposed)/x.swift b/\(decomposed)/x.swift
        --- a/\(decomposed)/x.swift
        +++ b/\(decomposed)/x.swift
        @@ -4 +4 @@
        diff --git a/Cafes/y.swift b/Cafes/y.swift
        --- a/Cafes/y.swift
        +++ b/Cafes/y.swift
        @@ -5 +5 @@

        """

        let expected = ["x.swift": [DiffHunk(start: 4, count: 1)]]

        #expect(GitChanges.hunks(inDiff: diff, packagePath: "Caf\u{E9}") == expected)
        #expect(GitChanges.hunks(inDiff: diff, packagePath: decomposed) == expected)
    }

    @Test("""
        git's diff of files named with a CR and a BEL, and of one starting with a combining mark, files each \
        file's hunk under its name (design B34, B35)
        """)
    func oddNamesFromGit() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let names = ["Pkg/x\ry.swift", "Pkg/b\u{7}z.swift", "Pkg/\u{301}w.swift"]
        try repository.write(Dictionary(uniqueKeysWithValues: names.map { ($0, "let a = 1\nlet b = 2\n") }))
        let before = try repository.commit("Odd names", day: 0)
        try repository.write(Dictionary(uniqueKeysWithValues: names.map { ($0, "let a = 1\nlet b = 20\n") }))
        let after = try repository.commit("Change line 2", day: 1)

        let hunks = try GitChanges.hunks(
            from: before,
            to: after,
            packagePath: "Pkg",
            in: repository.root.appendingPathComponent("Pkg")
        )

        #expect(hunks == [
            "x\ry.swift": [DiffHunk(start: 2, count: 1)],
            "b\u{7}z.swift": [DiffHunk(start: 2, count: 1)],
            "\u{301}w.swift": [DiffHunk(start: 2, count: 1)]
        ])
    }
}
