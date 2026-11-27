//
//  ResultsFileDraft.swift
//  SwiftStatsCoreTests
//
//  A generated results.jsonl (M6, design §2) as decisions: its lines in
//  order, the pool of keys its `mutant`, `retired` and header lines name,
//  and how its lines break. Each line carries a tag, its place in the list
//  as first drawn, which its text holds (a `mutant` line's description, a
//  header's not-covered entries', a `stopped` line's step), so a reader's
//  result names the line it came from even after lines move (P3.7).
//

import Foundation
@testable import SwiftStatsCore

/// A generated results file, as decisions.
struct ResultsFileDraft: Sendable {
    /// One line and its tag.
    struct Line: Sendable {
        /// Its place in the list as first drawn.
        let tag: Int
        /// The line.
        let draft: ResultsLineDraft
    }

    /// The lines, in file order.
    let lines: [Line]
    /// The keys the lines name, by index.
    let keys: [MutantKey]
    /// Whether each line ends with CRLF rather than LF.
    let crlf: Bool
    /// Whether the last line ends with a line break.
    let finalBreak: Bool

    /// The file's bytes: each line's, then its line break, but the last
    /// when `finalBreak` is false.
    var data: Data {
        let lineBreak: [UInt8] = crlf ? [ResultsLineRenderer.carriageReturn, ResultsLineRenderer.lineFeed]
            : [ResultsLineRenderer.lineFeed]
        var bytes: [UInt8] = []
        for (index, line) in lines.enumerated() {
            bytes += ResultsLineRenderer.bytes(of: line, keys: keys)
            if index < lines.count - 1 || finalBreak {
                bytes += lineBreak
            }
        }
        return Data(bytes)
    }

    /// The same file with `lines` in place of its lines.
    func replacing(lines: [Line]) -> Self {
        Self(lines: lines, keys: keys, crlf: crlf, finalBreak: finalBreak)
    }
}
