//
//  MeasuredCopy.swift
//  SwiftStatsCore
//
//  One clone copy with a mapped line (M5, uneven clone testing): its line
//  coverage over its inclusive range, the lines in it no test ran, and the
//  family naming it.
//

/// A clone copy and its line coverage.
struct MeasuredCopy {
    /// The copy.
    let instance: CloneInstance
    /// Its mapped lines, and how many ran.
    let tally: CoverageTally
    /// Its mapped lines that didn't run.
    let uncovered: [Int]
    /// The family naming it, by M4's copy-to-family rule; `<file>:<line>`
    /// when no family holds it.
    let family: String

    /// The share of its mapped lines that ran, from 0 to 1.
    var share: Double {
        Double(tally.covered) / Double(max(tally.total, 1))
    }

    /// Its file.
    var file: String {
        instance.file
    }

    /// Its first line.
    var start: Int {
        instance.range.start.line
    }

    /// Its last line.
    var end: Int {
        instance.range.end.line
    }

    /// The copy as an item lists it.
    var listed: SignalItem.CoveredCopy {
        SignalItem.CoveredCopy(file: file, line: start, family: family, covered: tally.covered, mapped: tally.total)
    }

    /// Whether this copy lies inside `other`: the same file, within its lines.
    func lies(inside other: Self) -> Bool {
        file == other.file && other.start <= start && end <= other.end
    }
}
