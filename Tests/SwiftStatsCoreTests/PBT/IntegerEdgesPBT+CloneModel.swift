//
//  IntegerEdgesPBT+CloneModel.swift
//  SwiftStatsCoreTests
//
//  The clone path's model, worked out apart from the mapper from the
//  collector's and the mapper's stated rules: which copy a run is refused
//  for, the range a taken copy is attached at (its end made inclusive,
//  shifted past a byte order mark on line 1 and kept at `Int.max` when
//  that would pass it), what the property's tally and the generator's
//  meta-test count, the laws each attached copy meets, and the planted
//  defect's mapping (B25's 04b undone as a wrapping add).
//

@testable import SwiftStatsCore

/// The clone path's model.
extension IntegerEdgesPBT {
    /// The span from `startLine`:`startColumn` to `endLine`:`endColumn`.
    static func span(_ startLine: Int, _ startColumn: Int, _ endLine: Int, _ endColumn: Int) -> SourceSpan {
        SourceSpan(
            start: SourcePosition(line: startLine, column: startColumn),
            end: SourcePosition(line: endLine, column: endColumn)
        )
    }

    /// Why the collector refuses `copy`: a position below 1, or an end
    /// before its start; nil when it doesn't (PRD §7.12, the adapter's
    /// `checkPositions`).
    static func malformation(of copy: CloneEdgeDraft.Copy) -> String? {
        if [copy.start.line, copy.start.column, copy.end.line, copy.end.column].contains(where: { $0 < 1 }) {
            return "has a position below 1"
        }
        return copy.end < copy.start ? "ends before it starts" : nil
    }

    /// `position` of a copy in a file starting with a byte order mark when
    /// `marked`, in records' columns: on line 1, three columns on, or
    /// `Int.max` when that would pass it.
    static func shifted(_ position: CloneEdgeDraft.Position, marked: Bool) -> SourcePosition {
        guard marked, position.line == 1 else {
            return SourcePosition(line: position.line, column: position.column)
        }
        let room = Int.max - ParsedFile.byteOrderMarkLength
        let column = position.column > room ? Int.max : position.column + ParsedFile.byteOrderMarkLength
        return SourcePosition(line: 1, column: column)
    }

    /// The range `copy`, one the collector takes, is attached at: its end
    /// column made inclusive, both ends shifted past a byte order mark.
    static func range(of copy: CloneEdgeDraft.Copy) -> SourceSpan {
        let last = CloneEdgeDraft.Position(line: copy.end.line, column: copy.end.column - 1)
        return SourceSpan(start: shifted(copy.start, marked: copy.marked), end: shifted(last, marked: copy.marked))
    }

    /// Whether `span` holds `range`.
    static func holds(_ span: SourceSpan, _ range: SourceSpan) -> Bool {
        span.start <= range.start && range.end <= span.end
    }

    /// The classes `draft` falls in, for the clone path's tally and the
    /// generator's meta-test: the run's first fault, else whether its
    /// copies are held by a record or by none, and whether a column after
    /// a byte order mark saturates; and its edges.
    static func cloneLabels(of draft: CloneEdgeDraft) -> [String] {
        let numbers = draft.copies.flatMap { [$0.start.line, $0.start.column, $0.end.line, $0.end.column] }
            + [draft.mass, draft.lineSpan] + draft.duplicatedLines
        let edges = edgeLabels(numbers)
        if let fault = draft.copies.lazy.compactMap(malformation(of:)).first {
            return [failed, fault == "has a position below 1" ? belowOne : inverted] + edges
        }
        let room = Int.max - ParsedFile.byteOrderMarkLength
        let held = draft.copies.map { copy in
            (recordSpans[copy.path] ?? []).contains { holds($0, range(of: copy)) }
        }
        let saturates = draft.copies.contains { copy in
            copy.marked && ((copy.start.line == 1 && copy.start.column > room)
                || (copy.end.line == 1 && copy.end.column - 1 > room))
        }
        return [
            (held.contains(true), mapped), (held.contains(false), unknown), (saturates, saturated)
        ]
        .filter(\.0)
        .map(\.1) + edges
    }

    /// The laws `instance` must meet on `library`: held by the one record
    /// holding its range, if any, covering exactly the records its range
    /// holds, and counting the lines holding a token within its lines.
    static func checkInstance(_ instance: CloneInstance, library: Library) -> [(holds: Bool, law: String)] {
        let records = library.records(in: instance.file)
        let holding = records.filter { holds($0.range, instance.range) }.map(\.key)
        let whole = records.filter { holds(instance.range, $0.range) }.map(\.key)
        let tokenCount = tokenLines[instance.file].map { lines in
            let low = max(lines.lowerBound, instance.range.start.line)
            let high = min(lines.upperBound, instance.range.end.line)
            return high < low ? 0 : high - low + 1
        } ?? 0
        return [
            (
                holding.count <= 1 && instance.containing == holding.first,
                "holds the copy at \(instance.range) by \(String(describing: instance.containing)), expected \(holding)"
            ),
            (Set(instance.wholes) == Set(whole), "covers \(instance.wholes) whole, expected \(whole)"),
            (
                instance.strippedLines == tokenCount,
                "counts \(instance.strippedLines) token lines, expected \(tokenCount)"
            )
        ]
    }

    /// `mapping` with every copy on line 1 of a file starting with a byte
    /// order mark shifted again as B25's 04b did before its fix, but with a
    /// wrapping add instead of a trapping one: the planted defect.
    static func wrappingShift(_ mapping: CloneMapping, draft: CloneEdgeDraft) -> CloneMapping {
        let wrapped = { (position: CloneEdgeDraft.Position, marked: Bool) in
            SourcePosition(
                line: position.line,
                column: marked && position.line == 1
                    ? position.column &+ ParsedFile.byteOrderMarkLength : position.column
            )
        }
        let marked = Dictionary(draft.copies.map { ($0.path, $0.marked) }) { first, _ in first }
        let classes = mapping.report.classes.map { clone in
            CloneClass(
                ordinal: clone.ordinal,
                pass: clone.pass,
                exact: clone.exact,
                mass: clone.mass,
                similarity: clone.similarity,
                lineSpan: clone.lineSpan,
                fingerprint: clone.fingerprint,
                instances: clone.instances.map { instance in
                    let isMarked = marked[instance.file] == true
                    let copy = draft.copies.first { $0.path == instance.file && range(of: $0) == instance.range }
                    let start = copy.map { wrapped($0.start, isMarked) } ?? instance.range.start
                    let end = copy.map { wrapped(.init(line: $0.end.line, column: $0.end.column - 1), isMarked) }
                    return CloneInstance(
                        file: instance.file,
                        range: SourceSpan(start: start, end: end ?? instance.range.end),
                        strippedLines: instance.strippedLines,
                        containing: instance.containing,
                        wholes: instance.wholes
                    )
                }
            )
        }
        let report = mapping.report
        return CloneMapping(
            report: CloneReport(
                part: report.part,
                fileListHash: report.fileListHash,
                toolDuplicatedLines: report.toolDuplicatedLines,
                classes: classes
            ),
            linesByFile: mapping.linesByFile
        )
    }
}
