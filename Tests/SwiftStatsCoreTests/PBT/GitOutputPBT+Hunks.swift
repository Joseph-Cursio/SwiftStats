//
//  GitOutputPBT+Hunks.swift
//  SwiftStatsCoreTests
//
//  P14.1's examples, each calling its shared check: CRLF files followed
//  by another file (design B5); paths at every edge the reader handles
//  (git's letter and octal escapes, B34; a mark starting the first
//  component, B35; a tab after a name with a space; a sibling folder; the
//  package in the other normalization form); a package at the top; the
//  diffs the property shrank B34's and B35's failures to (`CorpusEntry`);
//  and meta-tests that feed planted defects' readings to the check.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// P14.1's examples.
extension GitOutputPBT {
    /// The hunk P14.1's counterexamples shrank to: the old side's line 1,
    /// counting 0, with no lines.
    static let emptyHunk = DiffHunkDraft(
        start: 1,
        count: 0,
        writesOne: false,
        newStart: 1,
        newCount: 0,
        context: nil,
        removed: [],
        added: []
    )

    /// Diffs P14.1 shrank a failure to, with design B34's and B35's fixes
    /// each taken out in turn: a path git quotes for a CR, and a first
    /// component below the package starting with a combining mark.
    static let hunkCorpus = [
        CorpusEntry(
            input: DiffDraft(
                package: "",
                written: "",
                files: [markedFile(1, place: .inPackage, folders: ["x\ry"], mark: nil, hunks: [emptyHunk])]
            ),
            pins: "B34: a path git quoted for a CR, \"a/x\\ry/F1.swift\", read as xry/F1.swift"
        ),
        CorpusEntry(
            input: DiffDraft(
                package: "Caf\u{E9}",
                written: "Caf\u{E9}",
                files: [markedFile(1, place: .inPackage, folders: [], mark: "\u{301}", hunks: [emptyHunk])]
            ),
            pins: "B35: Caf\\u{E9}/\\u{301}F1.swift, its first component led by a mark, read as outside the package"
        )
    ]

    /// A hunk of the old side `start` and `count`, removing one line.
    static func hunk(_ start: Int, _ count: Int) -> DiffHunkDraft {
        hunk(start, count, removed: ["let a = 1"])
    }

    /// A hunk of the old side `start` and `count`, removing `removed`, as
    /// many as the count says, and adding one line.
    static func hunk(_ start: Int, _ count: Int, removed: [String]) -> DiffHunkDraft {
        DiffHunkDraft(
            start: start,
            count: count,
            writesOne: false,
            newStart: start,
            newCount: 1,
            context: nil,
            removed: removed.map { Array($0.utf8) },
            added: [Array("let a = 2".utf8)]
        )
    }

    /// File `number` of an example diff, changed, in the package, its lines
    /// ending as `ending`.
    static func plainFile(_ number: Int, ending: DiffFileDraft.Ending, hunks: [DiffHunkDraft]) -> DiffFileDraft {
        DiffFileDraft(
            kind: .changed,
            place: .inPackage,
            folders: [],
            mark: nil,
            number: number,
            octalHigh: false,
            ending: ending,
            hunks: hunks,
            endsWithoutNewline: false
        )
    }

    /// File `number` of an example diff, of `kind`, at `place`, named by
    /// its number alone, its lines ending in CR LF.
    static func file(
        _ number: Int,
        kind: DiffFileDraft.Kind,
        place: DiffFileDraft.Place,
        hunks: [DiffHunkDraft]
    ) -> DiffFileDraft {
        DiffFileDraft(
            kind: kind,
            place: place,
            folders: [],
            mark: nil,
            number: number,
            octalHigh: false,
            ending: .carriageReturnLineFeed,
            hunks: hunks,
            endsWithoutNewline: false
        )
    }

    /// File `number` of an example diff, changed, at `place`, below
    /// `folders`, `mark` starting its first component, its lines ending in
    /// CR LF.
    static func markedFile(
        _ number: Int,
        place: DiffFileDraft.Place,
        folders: [String],
        mark: String?,
        hunks: [DiffHunkDraft]
    ) -> DiffFileDraft {
        DiffFileDraft(
            kind: .changed,
            place: place,
            folders: folders,
            mark: mark,
            number: number,
            octalHigh: false,
            ending: .carriageReturnLineFeed,
            hunks: hunks,
            endsWithoutNewline: false
        )
    }

    /// The hunks `draft`'s diff reads as.
    static func read(_ draft: DiffDraft) -> [String: [DiffHunk]] {
        GitChanges.hunks(inDiff: GitChanges.text(of: draft.data), packagePath: draft.package)
    }

    /// `text` with each LF after a CR removed, so a line ending in CR LF
    /// runs into the next, as splitting on `Character("\n")` reads it.
    static func joinedAfterCarriageReturns(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            if scalar != "\n" || previous != "\r" {
                scalars.append(scalar)
            }
            previous = scalar
        }
        return String(scalars)
    }

    @Test("a CRLF file's hunks, and the hunks of the file after it, come back in order under their own paths")
    func crlfDiffReadsBack() {
        let read = GitChanges.hunks(inDiff: GitChanges.text(of: Self.crlfDiff.data), packagePath: "Pkg")

        #expect(Self.checkHunks(Self.crlfDiff, read: read))
        #expect(Self.crlfDiff.expected == [
            "F1.swift": [DiffHunk(start: 2, count: 1), DiffHunk(start: 4, count: 2), DiffHunk(start: 8, count: 1)],
            "F2.swift": [DiffHunk(start: 3, count: 1)]
        ])
    }

    @Test("""
        a diff at the reader's edges comes back: escaped and octal paths, a tab after a spaced name, a leading \
        mark, a sibling folder left out, the largest numbers, a fake old-path line, the package decomposed
        """)
    func edgeDiffReadsBack() {
        let read = GitChanges.hunks(inDiff: GitChanges.text(of: Self.edgeDiff.data), packagePath: "Caf\u{E9}")

        #expect(Self.checkHunks(Self.edgeDiff, read: read))
        #expect(Self.edgeDiff.expected == [
            "x\ry/b\u{7}z/F1.swift": [DiffHunk(start: 5, count: 0)],
            "R\u{E9}sum\u{E9}/c\u{1}d/F2.swift": [DiffHunk(start: 7, count: 3), DiffHunk(start: 20, count: 1)],
            "\u{301}a b/F3.swift": [DiffHunk(start: 1, count: 1)],
            "F5.swift": [DiffHunk(start: Int.max, count: Int.max)],
            "F6.swift": [DiffHunk(start: 2, count: 1), DiffHunk(start: 6, count: 2)]
        ])
    }

    @Test("for a package at the top every old path is in it, each file's hunks under its whole path")
    func topDiffReadsBack() {
        let read = GitChanges.hunks(inDiff: GitChanges.text(of: Self.topDiff.data), packagePath: "")

        #expect(Self.checkHunks(Self.topDiff, read: read))
        #expect(Self.scalars(Self.topDiff.expected.keys) == Self.scalars([
            "Elsewhere/F1.swift", "x/\u{FE0F}F2.swift", "\u{600}x/F3.swift", "\u{903}F4.swift"
        ]))
    }

    @Test(
        "B34, B35: a diff P14.1 shrank a failure to comes back, its one file's hunk under its path",
        arguments: hunkCorpus
    )
    func hunkCorpusReadsBack(entry: CorpusEntry<DiffDraft>) {
        let draft = entry.input
        let read = GitChanges.hunks(inDiff: GitChanges.text(of: draft.data), packagePath: draft.package)

        #expect(Self.checkHunks(draft, read: read))
        #expect(Array(read.values) == [[DiffHunk(start: 1, count: 0)]])
    }

    @Test("a planted defect's reading fails P14.1's law")
    func hunkDefectsDetected() {
        let crlf = Self.read(Self.crlfDiff)
        let edge = Self.read(Self.edgeDiff)
        let letters: [Unicode.Scalar: Unicode.Scalar] = ["\r": "r", "\u{7}": "a"]
        let lettered = Dictionary(uniqueKeysWithValues: edge.map { key, hunks in
            (String(String.UnicodeScalarView(key.unicodeScalars.map { letters[$0] ?? $0 })), hunks)
        })
        let markless = edge.filter { $0.key.unicodeScalars.first.map(Self.markScalars.contains) != true }

        #expect(Self.checkHunks(Self.crlfDiff, read: crlf))
        #expect(Self.checkHunks(Self.edgeDiff, read: edge))
        PlantedDefect.expectDetected("lines split on Characters (B5 undone)", sourceLocation: #_sourceLocation) {
            let text = Self.joinedAfterCarriageReturns(GitChanges.text(of: Self.crlfDiff.data))
            return Self.checkHunks(Self.crlfDiff, read: GitChanges.hunks(inDiff: text, packagePath: "Pkg"))
        }
        PlantedDefect.expectDetected("the last hunk alone kept", sourceLocation: #_sourceLocation) {
            Self.checkHunks(Self.crlfDiff, read: crlf.mapValues { Array($0.suffix(1)) })
        }
        PlantedDefect.expectDetected("a left-out count read as 0", sourceLocation: #_sourceLocation) {
            let zeroed = crlf.mapValues { $0.map { DiffHunk(start: $0.start, count: $0.count == 1 ? 0 : $0.count) } }
            return Self.checkHunks(Self.crlfDiff, read: zeroed)
        }
        PlantedDefect.expectDetected("a letter escape read as its letter, B34", sourceLocation: #_sourceLocation) {
            Self.checkHunks(Self.edgeDiff, read: lettered)
        }
        PlantedDefect.expectDetected("a mark-led path read as outside, B35", sourceLocation: #_sourceLocation) {
            Self.checkHunks(Self.edgeDiff, read: markless)
        }
        PlantedDefect.expectDetected("a sibling folder read as the package", sourceLocation: #_sourceLocation) {
            Self.checkHunks(Self.edgeDiff, read: edge.merging(["F4.swift": [DiffHunk(start: 9, count: 1)]]) { $1 })
        }
    }
}
