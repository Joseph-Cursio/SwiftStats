//
//  DiffHunkDraft.swift
//  SwiftStatsCoreTests
//
//  One hunk of a zero-context diff as decisions, for P14.1: the old
//  side's start and count, whether a count of 1 is written (git leaves it
//  out; the reader takes either), the new side, the function context git
//  writes after the second `@@`, and the changed lines as bytes, which
//  may hold any text but a line feed, invalid UTF-8 included. The header
//  is rendered as git renders it, and only as many removed and added lines
//  as the counts say, at most the lines drawn.
//

@testable import SwiftStatsCore

/// One hunk of a zero-context diff as decisions.
struct DiffHunkDraft: Hashable, Sendable {
    /// The old side's first line.
    let start: Int
    /// The old side's line count.
    let count: Int
    /// Whether a count of 1 is written, as `-5,1`, where git writes `-5`.
    let writesOne: Bool
    /// The new side's first line.
    let newStart: Int
    /// The new side's line count.
    let newCount: Int
    /// The function context after the second `@@`, if any.
    let context: String?
    /// The removed lines' bytes, without the `-` or a line break.
    let removed: [[UInt8]]
    /// The added lines' bytes, without the `+` or a line break.
    let added: [[UInt8]]

    /// The hunk the reader should give: the old side.
    var expected: DiffHunk {
        DiffHunk(start: start, count: count)
    }

    /// The header, as git writes it: `@@ -start[,count] +start[,count] @@`
    /// and the context; on an added file the old side is `-0,0`, as git
    /// writes it there.
    func header(onAddedFile: Bool) -> String {
        let old = onAddedFile ? "-0,0" : "-\(start)" + (count == 1 && writesOne == false ? "" : ",\(count)")
        let new = "+\(newStart)" + (newCount == 1 ? "" : ",\(newCount)")
        return "@@ \(old) \(new) @@" + (context.map { " " + $0 } ?? "")
    }

    /// The changed lines as git writes them, without line breaks: as many
    /// removed lines as the old count says, then as many added lines as
    /// the new count says, each at most the lines drawn; an added file
    /// removes none.
    func lines(onAddedFile: Bool) -> [[UInt8]] {
        let removedLines = onAddedFile ? [] : removed.prefix(count).map { [UInt8(ascii: "-")] + $0 }
        return removedLines + added.prefix(newCount).map { [UInt8(ascii: "+")] + $0 }
    }
}
