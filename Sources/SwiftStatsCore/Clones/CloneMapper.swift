//
//  CloneMapper.swift
//  SwiftStatsCore
//
//  Attaches SwiftCloneDetector's merged classes to the scan's function
//  records (PRD §7.12). Each copy's exclusive end column becomes
//  inclusive, so a whole-function copy has exactly its record's range.
//  `containing` is the innermost record holding the copy; `wholes` are
//  the records it covers whole. Copies are sorted by position; classes
//  are numbered by their first copy, then pass, then mass, largest first,
//  so the numbering doesn't depend on the order the tool reported them in.
//

import SwiftSyntax

/// Maps clone classes onto records.
struct CloneMapper {
    /// A merged class with its copies attached and sorted.
    private struct Draft {
        /// Its place in the merge's order.
        let index: Int
        /// The merged class.
        let merged: PassClone
        /// Its copies, sorted.
        let instances: [CloneInstance]

        /// Classes by first copy, then pass from the most specific, then
        /// mass, largest first, then the merge's order.
        static func order(_ lhs: Self, _ rhs: Self) -> Bool {
            if let left = lhs.instances.first, let right = rhs.instances.first, left != right {
                return CloneMapper.instanceOrder(left, right)
            }
            if lhs.merged.pass.specificity != rhs.merged.pass.specificity {
                return lhs.merged.pass.specificity < rhs.merged.pass.specificity
            }
            if lhs.merged.clone.mass != rhs.merged.clone.mass {
                return lhs.merged.clone.mass > rhs.merged.clone.mass
            }
            return lhs.index < rhs.index
        }
    }

    /// Decimal places kept of a near-miss similarity.
    private static let similarityScale = 10_000.0

    /// Function records by file, in source order.
    private let recordsByFile: [String: [FunctionRecord]]
    /// The parsed files by path.
    private let parsedByPath: [String: ParsedFile]

    /// A mapper onto `measured`'s records and files.
    init(measured: ScanMeasurements) {
        recordsByFile = Dictionary(grouping: measured.records, by: \.file)
            .mapValues { $0.sorted(by: PackageScanner.recordOrder) }
        parsedByPath = Dictionary(measured.parsed.map { ($0.file.path, $0.file) }) { first, _ in first }
    }

    /// `value` to four decimal places.
    private static func rounded(_ value: Double) -> Double {
        (value * similarityScale).rounded() / similarityScale
    }

    /// Copies by file, then start, then end.
    private static func instanceOrder(_ lhs: CloneInstance, _ rhs: CloneInstance) -> Bool {
        if lhs.file != rhs.file {
            return lhs.file < rhs.file
        }
        if lhs.range.start != rhs.range.start {
            return lhs.range.start < rhs.range.start
        }
        return lhs.range.end < rhs.range.end
    }

    /// `run`'s classes merged, attached and numbered; nil unless it ran.
    func mapping(of run: CloneRun) -> CloneMapping? {
        guard run.status.state == .ran else {
            return nil
        }
        let outputs = run.outputs
        var tokenLines: [String: Set<Int>] = [:]
        var covered: [String: Set<Int>] = [:]
        let drafts = CloneMerge.merged(outputs).enumerated().map { index, merged in
            let instances = merged.clone.instances.map { raw -> CloneInstance in
                if tokenLines[raw.path] == nil {
                    tokenLines[raw.path] = lines(of: raw.path)
                }
                let range = span(of: raw)
                let held = (tokenLines[raw.path] ?? []).filter { (range.start.line...range.end.line).contains($0) }
                covered[raw.path, default: []].formUnion(held)
                return instance(raw.path, range: range, strippedLines: held.count)
            }
            return Draft(index: index, merged: merged, instances: instances.sorted(by: Self.instanceOrder))
        }
        let classes = drafts.sorted(by: Draft.order).enumerated().map { offset, draft in
            CloneClass(
                ordinal: offset + 1,
                pass: draft.merged.pass,
                exact: draft.merged.exact,
                mass: draft.merged.clone.mass,
                similarity: draft.merged.clone.similarity.map(Self.rounded),
                lineSpan: draft.merged.clone.lineSpan,
                fingerprint: draft.merged.clone.fingerprint,
                instances: draft.instances
            )
        }
        let report = CloneReport(
            part: SwiftCloneDetectorAdapter.part,
            fileListHash: run.fileListHash,
            toolDuplicatedLines: CloneReport.DuplicatedLines(
                subtree: outputs[.subtree]?.duplicatedLines ?? 0,
                type1: outputs[.type1]?.duplicatedLines ?? 0,
                sequence: outputs[.sequence]?.duplicatedLines ?? 0,
                nearMiss: outputs[.nearMiss]?.duplicatedLines ?? 0
            ),
            classes: classes
        )
        return CloneMapping(report: report, linesByFile: covered)
    }

    /// `raw`'s range with an inclusive end, in records' columns.
    private func span(of raw: CloneDetectorOutput.Instance) -> SourceSpan {
        let offset = parsedByPath[raw.path]?.hasByteOrderMark == true ? ParsedFile.byteOrderMarkLength : 0
        let column = { (line: Int, column: Int) in line == 1 ? column + offset : column }
        return SourceSpan(
            start: SourcePosition(line: raw.startLine, column: column(raw.startLine, raw.startColumn)),
            end: SourcePosition(line: raw.endLine, column: column(raw.endLine, raw.endColumn - 1))
        )
    }

    /// The copy at `range` of `file`, attached to the records there.
    private func instance(_ file: String, range: SourceSpan, strippedLines: Int) -> CloneInstance {
        let records = recordsByFile[file] ?? []
        let holding = records.filter { $0.range.start <= range.start && range.end <= $0.range.end }
        let innermost = holding.min { lhs, rhs in
            if lhs.range.start != rhs.range.start {
                return lhs.range.start > rhs.range.start
            }
            if lhs.range.end != rhs.range.end {
                return lhs.range.end < rhs.range.end
            }
            return lhs.key < rhs.key
        }
        let wholes = records.filter { range.start <= $0.range.start && $0.range.end <= range.end }.map(\.key)
        return CloneInstance(
            file: file,
            range: range,
            strippedLines: strippedLines,
            containing: innermost?.key,
            wholes: wholes
        )
    }

    /// The lines of `path` holding a token, attributes excluded, as a
    /// record's stripped lines are counted; empty for a file not parsed.
    private func lines(of path: String) -> Set<Int> {
        guard let file = parsedByPath[path] else {
            return []
        }
        let converter = SourceLocationConverter(fileName: file.path, tree: file.tree)
        var lines = Set<Int>()
        for token in file.tree.tokens(viewMode: .sourceAccurate)
        where token.presence == .present && token.tokenKind != .endOfFile
            && FileContext.isAttributeToken(token) == false {
            let first = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
            let last = converter.location(for: token.endPositionBeforeTrailingTrivia).line
            lines.formUnion(first...max(first, last))
        }
        return lines
    }
}
