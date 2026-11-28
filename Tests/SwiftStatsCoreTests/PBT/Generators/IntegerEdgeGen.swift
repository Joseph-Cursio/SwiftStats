//
//  IntegerEdgeGen.swift
//  SwiftStatsCoreTests
//
//  P15.1's inputs (design §4.1.8, B25): tool records whose every numeric
//  field is an integer edge, 0, 1, or `Int.max - 3` through `Int.max`,
//  the values that trapped SwiftStats three times (`39c8676`, `3d69187`,
//  B1). One generator per decoder-to-mapper path: a swift-clone-detector
//  report of one class of two copies, in a file with a byte order mark or
//  without; a results.jsonl file of one header, listing one mutant not
//  covered, and one `mutant` line; a SwiftLint report of two violations
//  and a SwiftProjectLint report of one issue at two lines, in the scanned
//  file or one the scan never read; an outskirts run of two entries; and
//  two type-check timing lines. 1 is drawn three times as often as each
//  other edge: it is the only edge that puts a position in a file (line 1,
//  column 1, where a byte order mark shifts columns), the only schema
//  version SwiftProjectLint's reader takes, and the field a session must
//  match. A copy is sometimes written with its ends in order, so a
//  report is mapped often enough to check. Every list is ordered simplest
//  first, so a failure shrinks toward 0, then 1.
//

import PropertyBased

/// Generators of tool records whose numbers are integer edges.
enum IntegerEdgeGen {
    /// How far below `Int.max` the edges start (forced: the design names
    /// `Int.max - 3` through `Int.max`).
    static let belowMaximum = 3
    /// The edges, simplest first: 0, 1, then `Int.max - 3` up to `Int.max`.
    static let edges = [0, 1] + Array((Int.max - belowMaximum)...Int.max)
    /// How many times 1 is listed among the edges drawn.
    static let oneRepeats = 3
    /// The edges as drawn, simplest first: 0, then 1 three times, then
    /// `Int.max - 3` up to `Int.max`, so 1 comes three times as often as
    /// each other edge.
    static let drawn = [0] + Array(repeating: 1, count: oneRepeats) + edges.filter { $0 > 1 }

    /// An edge, 1 drawn three times as often as each other one; shrinks
    /// toward 0, then 1.
    static let edge = Pick.element(of: drawn)

    /// The scanned file without a byte order mark, as tools name it from
    /// the package root.
    static let plainFile = "Sources/Lib/Plain.swift"
    /// The scanned file starting with a byte order mark.
    static let markedFile = "Sources/Lib/Marked.swift"
    /// A Swift file in the package, outside every target's directory, so
    /// the scan never reads it.
    static let unscannedFile = "Unscanned/Other.swift"

    /// Whether a record lies in the scanned file, or in one the scan never
    /// read.
    static let scanned = Pick.element(of: [true, false])

    /// One copy: its file, its four positions, and whether its ends are
    /// written in order.
    static let copy = zip(
        Pick.element(of: [false, true]),
        edge,
        edge,
        edge,
        edge,
        Pick.element(of: [false, true])
    )
    .map { marked, startLine, startColumn, endLine, endColumn, ordered in
        CloneEdgeDraft.Copy(
            marked: marked,
            first: CloneEdgeDraft.Position(line: startLine, column: startColumn),
            second: CloneEdgeDraft.Position(line: endLine, column: endColumn),
            ordered: ordered
        )
    }

    /// A swift-clone-detector report: one class of two copies, its mass and
    /// line span, and each pass's duplicated-line count.
    static let clones = zip(copy, copy, edge, edge, edge.array(of: CloneEdgeDraft.passCount))
        .map { first, second, mass, lineSpan, duplicated in
            CloneEdgeDraft(copies: [first, second], mass: mass, lineSpan: lineSpan, duplicatedLines: duplicated)
        }

    /// A mutant key's numbers: line, column and occurrence.
    static let keyNumbers = zip(edge, edge, edge).map { line, column, occurrence in
        ResultsEdgeDraft.KeyNumbers(line: line, column: column, occurrence: occurrence)
    }

    /// A results file: the header's session and its one not-covered key,
    /// and the `mutant` line's session, key, exit status and failed-test
    /// count.
    static let results = zip(edge, keyNumbers, edge, keyNumbers, edge, edge)
        .map { headerSession, notCovered, mutantSession, tested, exitStatus, failedTestCount in
            ResultsEdgeDraft(
                headerSession: headerSession,
                notCovered: notCovered,
                mutantSession: mutantSession,
                tested: tested,
                exitStatus: exitStatus,
                failedTestCount: failedTestCount
            )
        }

    /// A SwiftLint violation: in the scanned file or not, at a line and a
    /// column.
    static let violation = zip(scanned, edge, edge).map { scanned, line, column in
        LintEdgeDraft.Violation(scanned: scanned, line: line, column: column)
    }

    /// A SwiftLint report of two violations, and a SwiftProjectLint report
    /// of a schema version and one issue at two lines, in the scanned file
    /// or not.
    static let lints = zip(violation, violation, edge, scanned, edge, edge)
        .map { first, second, schemaVersion, scanned, firstLine, secondLine in
            LintEdgeDraft(
                violations: [first, second],
                schemaVersion: schemaVersion,
                issueScanned: scanned,
                issueLines: [firstLine, secondLine]
            )
        }

    /// An outskirts entry's location: a line and a column.
    static let location = zip(edge, edge).map { line, column in
        OutskirtsEdgeDraft.Location(line: line, column: column)
    }

    /// An outskirts run of two unused free functions.
    static let outskirts = location.array(of: OutskirtsEdgeDraft.entryCount).map(OutskirtsEdgeDraft.init)

    /// A timing line: a whole number of milliseconds, a line and a column.
    static let timingLine = zip(edge, edge, edge).map { milliseconds, line, column in
        TimingEdgeDraft.Line(milliseconds: milliseconds, line: line, column: column)
    }

    /// Two function-body timing lines.
    static let timings = timingLine.array(of: TimingEdgeDraft.lineCount).map(TimingEdgeDraft.init)
}
