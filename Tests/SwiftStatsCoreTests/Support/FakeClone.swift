//
//  FakeClone.swift
//  SwiftStatsCoreTests
//
//  A clone class as a test has the fake SwiftCloneDetector report it:
//  the run that reports it, its mass, and its copies as whole lines of
//  files, so a test states which records a copy covers or sits in, or, for
//  a copy starting or ending inside a line, the column it starts at or
//  ends before.
//

/// A clone class for the fake SwiftCloneDetector to report.
struct FakeClone {
    /// The run reporting it: `default` (subtree), `--sequence` or `--type3`.
    let run: String
    /// Its mass.
    let mass: Int
    /// Its copies: a file and its lines, from `startColumn` of the first
    /// line to `endColumn` of the last.
    let spans: [(path: String, lines: ClosedRange<Int>)]
    /// Whether the `--type1` run reports it too, making a subtree class exact.
    var exact = false
    /// The column every copy starts at.
    var startColumn = 1
    /// The column every copy ends before, as the tool reports ends; nil for
    /// past the end of any line.
    var endColumn: Int?
}
