import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the git output generators draw (design D14): from a fixed seed, a
/// thousand diffs reach each antecedent of P14.1 an exact number of times
/// (CR-ended changed lines before a hunk or a file header that matters,
/// quoted paths with letter and octal escapes, a tab after a spaced name,
/// a mark starting the first component, files beside, above and outside
/// the package, added, deleted, renamed and hunkless files, counts left
/// out, 0 and the largest, a fake old-path line, invalid UTF-8, the
/// package in the other normalization form or at the top), and a thousand
/// listings reach each antecedent of P14.2 (whole copies, renames and
/// deletions, paths spelled like a status, holding a line break or led by
/// a byte order mark, and cuts between entries, after a status and after a
/// first path). The
/// counts hold under this engine's generator code and this standard
/// library; a change to either, or to a weight or list in `GitDiffGen` or
/// `NameStatusGen`, redraws them. Hand-worked examples pin the rendering
/// to git's: the bytes of a CRLF diff, and each header path as git quoted
/// it in a scratch repository (step 15b's probe).
@Suite("git output generators")
struct GitOutputGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: only scalars reject a value (a
    /// surrogate), so a few are always enough at this seed.
    static let attempts = 10
    /// The fixed seed the meta-tests draw from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    @Test("a thousand diffs reach each antecedent of P14.1 an exact number of times")
    func diffClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let draft = try GitDiffGen.diff.run(using: &random, limit: Self.attempts)
            for label in GitOutputPBT.diffLabels(of: draft) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "a CR-ended changed line before another hunk of a file in the package": 259,
            "a CR-ended changed line before the next file's header, which would show": 138,
            "a changed line that isn't UTF-8": 504,
            "a count of 0": 355,
            "a count of 1 left out": 316,
            "a deleted file in the package with hunks": 50,
            "a file in the package giving no hunks": 406,
            "a file with hunks in a folder whose name starts with the package's": 69,
            "a file with hunks outside the package": 162,
            "a package at the top with hunks": 68,
            "a path in the package holding a control git writes as a letter, not t or n": 183,
            "a path whose first component below the package starts with a mark": 153,
            "a quoted path in the package": 432,
            "a removed line like an old-path line before a later hunk of its file": 88,
            "a renamed file in the package with hunks": 47,
            "an added file with hunks": 61,
            "an octal escape in a path in the package": 213,
            "an old-path line in the package ending in a tab": 146,
            "the largest start or count": 199,
            "the package written in the other normalization form": 79
        ])
    }

    @Test("a thousand listings reach each antecedent of P14.2 an exact number of times")
    func listingClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let draft = try NameStatusGen.listing.run(using: &random, limit: Self.attempts)
            for label in GitOutputPBT.listingLabels(of: draft) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "a listing cut after a copy's or rename's first path": 65,
            "a listing cut between entries": 172,
            "a listing cut just after a status": 178,
            "a whole copy": 358,
            "a whole deletion": 122,
            "a whole entry's path holding a line break or a CR": 240,
            "a whole entry's path spelled like a status": 412,
            "a whole entry's path starting with a byte order mark": 173,
            "a whole rename": 392
        ])
    }

    @Test("""
        a drafted diff renders as git writes it: headers and hunk headers in LF, a CRLF file's changed lines in \
        CR LF, a count of 1 left out, a removed blank line as a lone minus
        """)
    func diffRenders() {
        let text = """
        diff --git a/Pkg/F1.swift b/Pkg/F1.swift
        index 1111111..2222222 100644
        --- a/Pkg/F1.swift
        +++ b/Pkg/F1.swift
        @@ -2 +2 @@
        -let a = 1\r
        +let a = 2\r
        @@ -4,2 +4 @@
        -\r
        -let e = 5\r
        +let a = 2\r
        @@ -8 +8 @@
        -let a = 1\r
        +let a = 2\r
        diff --git a/Pkg/F2.swift b/Pkg/F2.swift
        index 1111111..2222222 100644
        --- a/Pkg/F2.swift
        +++ b/Pkg/F2.swift
        @@ -3 +3 @@
        -let a = 1\r
        +let a = 2\r

        """

        #expect(String(bytes: GitOutputPBT.crlfDiff.data, encoding: .utf8) == text)
    }

    @Test(
        "each header path is written as git wrote it in a scratch repository, quoted with its escapes",
        arguments: [
            ("a/Caf\u{E9}.swift", false, "a/Caf\u{E9}.swift"),
            ("a/b\u{7}z.swift", false, "\"a/b\\az.swift\""),
            ("a/back\\slash.swift", false, "\"a/back\\\\slash.swift\""),
            ("a/bs\u{8}q.swift", false, "\"a/bs\\bq.swift\""),
            ("a/c\u{1}d.swift", false, "\"a/c\\001d.swift\""),
            ("a/del\u{7F}x.swift", false, "\"a/del\\177x.swift\""),
            ("a/f\u{C}g.swift", false, "\"a/f\\fg.swift\""),
            ("a/q\"r.swift", false, "\"a/q\\\"r.swift\""),
            ("a/sp ace.swift", false, "a/sp ace.swift\t"),
            ("a/t\tu.swift", false, "\"a/t\\tu.swift\""),
            ("a/v\u{B}w.swift", false, "\"a/v\\vw.swift\""),
            ("a/x\ry.swift", false, "\"a/x\\ry.swift\""),
            ("a/Caf\u{E9}.swift", true, "\"a/Caf\\303\\251.swift\"")
        ]
    )
    func pathsQuoted(name: String, octalHigh: Bool, written: String) {
        #expect(DiffDraft.pathLine(name, octalHigh: octalHigh) == written)
    }

    @Test("a drafted listing writes each status and path NUL-ended, a score in three digits, and cuts between fields")
    func listingRenders() {
        let entries = [
            NameStatusEntry(status: .renamed, score: 7, paths: ["old", "new"]),
            NameStatusEntry(status: .deleted, score: 0, paths: ["gone"])
        ]
        let whole = NameStatusDraft(entries: entries, cut: nil)
        let cut = NameStatusDraft(entries: entries, cut: NameStatusDraft.Cut(entry: 3, kept: 5))

        #expect(whole.data == Data("R007\u{0}old\u{0}new\u{0}D\u{0}gone\u{0}".utf8))
        #expect(cut.fields == ["R007", "old", "new", "D"])
        #expect(cut.expected == ["new"])
        #expect(cut.cutPaths.isEmpty)
    }
}
