//
//  CloneEdgeDraft.swift
//  SwiftStatsCoreTests
//
//  P15.1's clone input: one swift-clone-detector class of two copies whose
//  every number is an integer edge, each copy in the scanned file with a
//  byte order mark or the one without, written as the subtree run's JSON
//  report; the other three runs report no class, each with its own
//  duplicated-line count. A copy written in order has its ends sorted, so
//  only its fields can make it malformed.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// A swift-clone-detector class whose numbers are integer edges.
struct CloneEdgeDraft: Sendable, CustomTestStringConvertible {
    /// A line and column as the tool writes them.
    struct Position: Hashable, Sendable, Comparable {
        /// The 1-based line.
        let line: Int
        /// The 1-based UTF-8 column.
        let column: Int

        /// Line order, then column order.
        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.line, lhs.column) < (rhs.line, rhs.column)
        }
    }

    /// One copy as drafted.
    struct Copy: Hashable, Sendable {
        /// Whether it lies in the file starting with a byte order mark.
        let marked: Bool
        /// The first position drawn.
        let first: Position
        /// The second position drawn.
        let second: Position
        /// Whether the two are written in order, the earlier as the start.
        let ordered: Bool

        /// Its file, as the tool names it.
        var path: String {
            marked ? IntegerEdgeGen.markedFile : IntegerEdgeGen.plainFile
        }

        /// Where it starts, as written.
        var start: Position {
            ordered ? min(first, second) : first
        }

        /// The position just past its last character, as written.
        var end: Position {
            ordered ? max(first, second) : second
        }

        /// The copy as the report writes it.
        var json: String {
            "{\"path\": \"\(path)\", \"startLine\": \(start.line), \"startColumn\": \(start.column), "
                + "\"endLine\": \(end.line), \"endColumn\": \(end.column)}"
        }
    }

    /// The runs whose reports are drafted (forced: the four passes).
    static let passCount = CloneDetectorPass.runOrder.count
    /// The tool's name, as its reports write it.
    static let toolName = "swift-clone-detector"

    /// The class's two copies, in the tool's order.
    let copies: [Copy]
    /// The class's mass.
    let mass: Int
    /// The class's line span.
    let lineSpan: Int
    /// Each run's duplicated-line count, in `CloneDetectorPass.runOrder`.
    let duplicatedLines: [Int]

    /// The copies, the mass, the line span and each run's count.
    var testDescription: String {
        let shown = copies.map { copy in
            "\(copy.marked ? "marked" : "plain") \(copy.start.line):\(copy.start.column)-"
                + "\(copy.end.line):\(copy.end.column)"
        }
        return "copies [\(shown.joined(separator: ", "))], mass \(mass), line span \(lineSpan), "
            + "duplicated lines \(duplicatedLines)"
    }

    /// The duplicated-line count of `pass`'s run.
    func duplicatedLines(of pass: CloneDetectorPass) -> Int {
        CloneDetectorPass.runOrder.firstIndex(of: pass).map { duplicatedLines[$0] } ?? 0
    }

    /// `pass`'s report: the class for the subtree run, no class for the
    /// others.
    func report(of pass: CloneDetectorPass) -> Data {
        let clones = pass == .subtree
            ? "[{\"fingerprint\": \"0000000000000001\", \"mass\": \(mass), \"lineSpan\": \(lineSpan), "
                + "\"instances\": [\(copies.map(\.json).joined(separator: ", "))]}]"
            : "[]"
        return Data(
            """
            {"clones": \(clones), "duplicatedLines": \(duplicatedLines(of: pass)), "mode": "type1-2",
             "tool": "\(Self.toolName)", "version": "0.1.0"}
            """.utf8
        )
    }
}
