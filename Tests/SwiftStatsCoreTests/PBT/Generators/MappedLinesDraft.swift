//
//  MappedLinesDraft.swift
//  SwiftStatsCoreTests
//
//  Mapped lines as decisions, P2.4's input: each line's step from the one
//  before (the first's is ignored), its count, and whether it is partly
//  run, which only a line that ran can be (PRD §7.8); and where the lines
//  start, as segment lists' do (`SegmentListDraft.Anchor`). Steps are at
//  least 1, so the lines increase, as the line rule gives them. A failure
//  report lists the lines.
//

@testable import SwiftStatsCore
import Testing

/// Mapped lines as decisions.
struct MappedLinesDraft: Hashable, Sendable, CustomTestStringConvertible {
    /// One line as decisions.
    struct Line: Hashable, Sendable {
        /// How many lines after the one before it this one is, at least 1.
        let step: Int
        /// Its count.
        let executionCount: Int64
        /// Whether it is partly run, when it ran.
        let partlyRun: Bool
    }

    /// The lines, in order.
    let lines: [Line]
    /// Where their numbers start.
    let anchor: SegmentListDraft.Anchor

    /// The mapped lines the decisions make.
    var built: [CoverageLineIterator.Line] {
        let offsets = lines.indices.map { index in index == 0 ? 0 : lines[1...index].map(\.step).reduce(0, +) }
        let first: Int
        switch anchor {
        case .end:
            first = Int.max - (offsets.last ?? 0)

        case .start(let line):
            first = line
        }
        return zip(lines, offsets).map { line, offset in
            CoverageLineIterator.Line(
                line: first + offset,
                executionCount: line.executionCount,
                partlyRun: line.partlyRun && line.executionCount > 0
            )
        }
    }

    /// The lines, one `line:count` each, `*` marking a partly run one.
    var testDescription: String {
        let shown = built.map { "\($0.line):\($0.executionCount)" + ($0.partlyRun ? "*" : "") }
        return "\(built.count) lines: " + shown.joined(separator: " ")
    }
}
