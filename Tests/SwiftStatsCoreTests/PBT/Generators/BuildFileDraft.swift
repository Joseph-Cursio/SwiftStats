//
//  BuildFileDraft.swift
//  SwiftStatsCoreTests
//
//  One generated build-output file as decisions, before the interpreter
//  writes and labels it: its blocks of lines, a decoration per line (the
//  line at index i takes decoration i, and lines past the decorations are
//  written plain), and whether a line break ends the last line. Shrinking
//  drops blocks and decorations independently; any combination is valid.
//

/// A generated build-output file before it is written and labelled.
struct BuildFileDraft: Hashable, Sendable {
    /// The file's blocks, each one or more lines (a timing line, a
    /// diagnostic with its continuations, a recorded group).
    let blocks: [[BuildLineDraft]]
    /// The decorations of the file's lines, by index.
    let decorations: [BuildLineDecoration]
    /// Whether a line break ends the last line.
    let terminated: Bool
}
