//
//  TimingEdgeDraft.swift
//  SwiftStatsCoreTests
//
//  P15.1's timing input: two `-debug-time-function-bodies` lines on the
//  build's standard error, each a function body's time in whole
//  milliseconds, at a line and a column of the scanned file without a
//  byte order mark, every number an integer edge, as the compiler writes
//  them: `<ms>ms<TAB><path>:<line>:<column><TAB><declaration>`.
//

import Foundation
import Testing

/// Type-check timing lines whose numbers are integer edges.
struct TimingEdgeDraft: Sendable, CustomTestStringConvertible {
    /// One timing line as drafted.
    struct Line: Hashable, Sendable {
        /// Its time, in whole milliseconds.
        let milliseconds: Int
        /// Its 1-based line.
        let line: Int
        /// Its 1-based UTF-8 column.
        let column: Int
    }

    /// How many timing lines a draft has.
    static let lineCount = 2
    /// The declaration every line names.
    static let declaration = "global function first()"

    /// The lines, in order.
    let lines: [Line]

    /// Each line's time and place.
    var testDescription: String {
        "lines " + lines.map { "\($0.milliseconds)ms at \($0.line):\($0.column)" }.joined(separator: ", ")
    }

    /// The standard error, its paths under `root`.
    func standardError(root: String) -> Data {
        let text = lines.map { line in
            "\(line.milliseconds)ms\t\(root)/\(IntegerEdgeGen.plainFile):\(line.line):\(line.column)\t"
                + Self.declaration + "\n"
        }
        return Data(text.joined().utf8)
    }
}
