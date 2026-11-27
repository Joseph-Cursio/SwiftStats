//
//  BuildOutputSplitGen.swift
//  SwiftStatsCoreTests
//
//  Generated build output and a change to its files, for P1.8: a split of
//  the standard error between two lines, or one valid timing line moved
//  from the standard error into the task log. A split goes before a line
//  no message takes and that is no origin note, so neither half's reading
//  depends on the other's (the line before may still be a header or a
//  line its message took: then the message ended there); half the splits
//  go right after a message when there is such a place. A moved line is a
//  standard error line that reads as an entry; half the moves take one
//  right after a header or a line its message took, which ends that
//  message, when there is one. It goes into the log at a drawn place, with
//  a line feed when it had no line break, and the log's last line gets one
//  when the moved line goes after it. Choices are drawn as numbers and
//  taken modulo the places that qualify, so any choice fits any output.
//

import Foundation
import PropertyBased
import Testing

/// Generators of build output with a split or a moved timing line.
enum BuildOutputSplitGen {
    /// A generated output and where its standard error splits, P1.8's
    /// first input.
    struct Split: Sendable, CustomTestStringConvertible {
        /// The output as generated.
        let sample: GeneratedBuildOutput
        /// Whether the split prefers a place right after a message.
        let afterMessage: Bool
        /// Which of the qualifying places, modulo their count.
        let choice: Int

        /// The index of the standard error line the second half starts
        /// with; nil when no place qualifies.
        var index: Int? {
            let lines = sample.stderrLines
            let qualifying = lines.indices.dropFirst().filter { index in
                lines[index].reading != .continuation && BuildOutputSplitGen.isOrigin(lines[index].shape) == false
            }
            let preferred = qualifying.filter { BuildOutputGen.opensMessage(lines[$0 - 1].reading) }
            let places = afterMessage && preferred.isEmpty == false ? preferred : qualifying
            return BuildOutputSplitGen.chosen(choice, from: places)
        }

        /// Whether the split goes right after a header or a line its
        /// message took.
        var isAfterMessage: Bool {
            index.map { BuildOutputGen.opensMessage(sample.stderrLines[$0 - 1].reading) } ?? false
        }

        /// The standard error's first half; all of it when nothing splits.
        var first: Data {
            Data(sample.stderrLines.prefix(index ?? sample.stderrLines.count).flatMap(\.data))
        }

        /// The standard error's second half; nothing when nothing splits.
        var second: Data {
            Data(sample.stderrLines.dropFirst(index ?? sample.stderrLines.count).flatMap(\.data))
        }

        /// Where the split goes, and the output, in ASCII.
        var testDescription: String {
            "split before standard error line \(index.map(String.init) ?? "none")\n" + sample.testDescription
        }
    }

    /// A generated output and the timing line moved into its log, P1.8's
    /// second input.
    struct Move: Sendable, CustomTestStringConvertible {
        /// The output as generated.
        let sample: GeneratedBuildOutput
        /// Whether the move prefers a line that ends a message.
        let afterMessage: Bool
        /// Which of the qualifying lines, modulo their count.
        let choice: Int
        /// Where it goes in the log, modulo the places there.
        let position: Int

        /// The index of the standard error line moved; nil when no line
        /// reads as an entry.
        var index: Int? {
            let lines = sample.stderrLines
            let entries = lines.indices.filter { index in
                if case .entry = lines[index].reading {
                    return true
                }
                return false
            }
            let preferred = entries.filter { $0 > 0 && BuildOutputGen.opensMessage(lines[$0 - 1].reading) }
            let places = afterMessage && preferred.isEmpty == false ? preferred : entries
            return BuildOutputSplitGen.chosen(choice, from: places)
        }

        /// Whether the moved line came right after a header or a line its
        /// message took, so it ended that message.
        var endsMessage: Bool {
            guard let index, index > 0 else {
                return false
            }
            return BuildOutputGen.opensMessage(sample.stderrLines[index - 1].reading)
        }

        /// The index, among the entries read, of the moved line's entry.
        var entryIndex: Int? {
            index.map { BuildOutputSplitGen.entryCount(in: sample.stderrLines.prefix($0)) }
        }

        /// The moved line; nil when none moves.
        var moved: GeneratedBuildLine? {
            index.map { sample.stderrLines[$0] }
        }

        /// The standard error without the moved line.
        var stderr: Data {
            let lines = sample.stderrLines
            return Data(lines.indices.filter { $0 != index }.flatMap { lines[$0].data })
        }

        /// The log with the moved line at its place, ended by a line feed
        /// when it had no line break, the line before it given one when it
        /// had none; the log as generated when nothing moves.
        var log: Data {
            let lines = sample.logLines
            guard let moved else {
                return Data(lines.flatMap(\.data))
            }
            let place = position % (lines.count + 1)
            var written = lines.map { Data($0.written) + Data($0.lineBreak.utf8) }
            if place == lines.count, let last = lines.last, last.lineBreak.isEmpty {
                written[place - 1] += Data(BuildOutputSplitGen.lineFeed.utf8)
            }
            let lineBreak = moved.lineBreak.isEmpty ? BuildOutputSplitGen.lineFeed : moved.lineBreak
            written.insert(Data(moved.written) + Data(lineBreak.utf8), at: place)
            return Data(written.joined())
        }

        /// What moves where, and the output, in ASCII.
        var testDescription: String {
            let what = index.map { "move standard error line \($0) into the log, at \(position)" } ?? "move nothing"
            return what + "\n" + sample.testDescription
        }
    }

    /// The largest choice or position drawn (assumed: past most outputs'
    /// line counts, so choices modulo them spread over every line).
    static let choiceBound = 200
    /// The share of changes that prefer a place right after a message.
    static let afterMessageRate: Float = 0.5
    /// A line feed.
    static let lineFeed = "\n"

    /// Generated output under the decided rules and a split of its
    /// standard error.
    static let split = zip(
        BuildOutputGen.output(.decided),
        Gen.bool(afterMessageRate),
        Gen<Int>.value(in: 0...choiceBound)
    )
    .map { Split(sample: $0, afterMessage: $1, choice: $2) }

    /// Generated output under the decided rules and a timing line moved
    /// into its log.
    static let move = zip(
        BuildOutputGen.output(.decided),
        Gen.bool(afterMessageRate),
        Gen<Int>.value(in: 0...choiceBound),
        Gen<Int>.value(in: 0...choiceBound)
    )
    .map { Move(sample: $0, afterMessage: $1, choice: $2, position: $3) }

    /// The element of `places` at `choice`, modulo their count; nil when
    /// there are none.
    static func chosen(_ choice: Int, from places: [Int]) -> Int? {
        places.isEmpty ? nil : places[choice % places.count]
    }

    /// Whether `shape` is a macro expansion's origin note.
    static func isOrigin(_ shape: BuildLineShape) -> Bool {
        if case .origin = shape {
            return true
        }
        return false
    }

    /// How many of `lines` read as entries.
    static func entryCount(in lines: ArraySlice<GeneratedBuildLine>) -> Int {
        lines.count { line in
            if case .entry = line.reading {
                return true
            }
            return false
        }
    }
}
