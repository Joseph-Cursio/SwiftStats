//
//  ResultsFileGen+Changes.swift
//  SwiftStatsCoreTests
//
//  P3.7's inputs: a generated results file and a change that, by the
//  reading rules, changes only what P3.7 says. Appending a line that never
//  reads (`ResultsLineRenderer.garbage`) only grows the lines skipped. The
//  line goes after the file's last bytes: when the file ends in an empty
//  line with no line break, which has no bytes, the appended line takes
//  its place, since breaking that empty line first would make it a lone
//  CR under CRLF breaks, a second line skipped.
//  Interleaving each run of consecutive `mutant` lines differently, each
//  key's lines kept in their order, keeps the mutants and the count
//  tested: the last line of a key still wins, and nothing between the
//  lines moves. Keys compare as `MutantKey` compares them, so both
//  spellings of a path keep their order. Each line keeps its tag, so a
//  result names the same line after the move.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P3.7's inputs.
extension ResultsFileGen {
    /// A file, and the same file with a line that never reads appended.
    struct Appended: Sendable, CustomTestStringConvertible {
        /// The file.
        let file: GeneratedResultsFile
        /// The file with the line appended.
        let appended: GeneratedResultsFile

        /// The file, then the line appended.
        var testDescription: String {
            let line = appended.draft.lines.last.map { ResultsLineRenderer.bytes(of: $0, keys: appended.draft.keys) }
            return file.testDescription + "\n" + PBTTrace.ascii("appended: " + GeneratedResultsFile.shown(line ?? []))
        }
    }

    /// A file, and the same file with its runs of `mutant` lines
    /// interleaved otherwise.
    struct Reordered: Sendable, CustomTestStringConvertible {
        /// The file.
        let file: GeneratedResultsFile
        /// The file with its runs reordered.
        let reordered: GeneratedResultsFile

        /// Whether any line moved.
        var moved: Bool {
            file.draft.lines.map(\.tag) != reordered.draft.lines.map(\.tag)
        }

        /// The file, then the tags in their new order.
        var testDescription: String {
            let tags = reordered.draft.lines.map { "\($0.tag)" }.joined(separator: " ")
            return file.testDescription + "\nreordered tags: " + tags
        }
    }

    /// A file and the same file with a line that never reads appended.
    static let appended = zip(file, Gen<Int>.value(in: ResultsLineRenderer.garbage.indices))
        .map { file, garbage in
            Appended(file: file, appended: GeneratedResultsFile(draft: appending(garbage, to: file.draft)))
        }

    /// A file and the same file with its runs of `mutant` lines interleaved
    /// by drawn picks.
    static let reordered = zip(file, Gen<Int>.value(in: 0...largestPick).array(of: lineCount))
        .map { file, picks in
            let lines = interleaved(file.draft.lines, keys: file.draft.keys, picks: picks)
            return Reordered(file: file, reordered: GeneratedResultsFile(draft: file.draft.replacing(lines: lines)))
        }

    /// `draft` with the garbage line at `garbage` appended after its last
    /// bytes: in place of a last empty line with no line break, else after
    /// its last line.
    static func appending(_ garbage: Int, to draft: ResultsFileDraft) -> ResultsFileDraft {
        var lines = draft.lines
        if draft.finalBreak == false, case .blank = lines.last?.draft {
            lines.removeLast()
        }
        lines.append(ResultsFileDraft.Line(tag: draft.lines.count, draft: .garbage(garbage)))
        return draft.replacing(lines: lines)
    }

    /// `lines` with each run of consecutive `mutant` lines interleaved by
    /// `picks`, used in turn and around, each key's lines in their order;
    /// every other line stays where it is.
    static func interleaved(
        _ lines: [ResultsFileDraft.Line],
        keys: [MutantKey],
        picks: [Int]
    ) -> [ResultsFileDraft.Line] {
        var result: [ResultsFileDraft.Line] = []
        var run: [ResultsFileDraft.Line] = []
        var turn = 0
        for line in lines {
            if case .mutant = line.draft {
                run.append(line)
                continue
            }
            result += interleaving(run, keys: keys, picks: picks, turn: &turn)
            run = []
            result.append(line)
        }
        return result + interleaving(run, keys: keys, picks: picks, turn: &turn)
    }

    /// The `mutant` lines `run`, one queue per key in order of first
    /// appearance, merged by taking the head of the queue the next pick
    /// names, counted around the queues left.
    private static func interleaving(
        _ run: [ResultsFileDraft.Line],
        keys: [MutantKey],
        picks: [Int],
        turn: inout Int
    ) -> [ResultsFileDraft.Line] {
        var queueKeys: [MutantKey] = []
        var queues: [[ResultsFileDraft.Line]] = []
        for line in run {
            guard case let .mutant(mutant) = line.draft else {
                continue
            }
            let key = ResultsLineObjects.key(at: mutant.key, in: keys)
            if let index = queueKeys.firstIndex(of: key) {
                queues[index].append(line)
            } else {
                queueKeys.append(key)
                queues.append([line])
            }
        }
        var merged: [ResultsFileDraft.Line] = []
        while queues.isEmpty == false {
            let pick = picks.isEmpty ? 0 : picks[turn % picks.count]
            turn += 1
            let index = pick % queues.count
            merged.append(queues[index].removeFirst())
            if queues[index].isEmpty {
                queues.remove(at: index)
            }
        }
        return merged
    }
}
