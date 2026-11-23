//
//  PositionPlacement.swift
//  SwiftStatsCore
//
//  Where something at a position of a kept file goes (M5, M6): coverage
//  places an export entry by the start of its first region, mutation a
//  mutant by its anchor. The position, compared by (line, column), goes to
//  the innermost production record holding it (the latest start, then the
//  earliest end, then the key; a file's top-level-code record only on its
//  statement lines), else to the innermost type holding it, else to its
//  file. Columns compare as they are: the records count a byte order
//  mark's bytes on line 1, and callers give positions counted the same
//  way. Given an end, a span ending past its record is unmapped.
//

/// Places positions on records, types and files.
struct PositionPlacement {
    /// Where a position goes.
    enum Place: Hashable {
        /// To the record with this key.
        case record(String)
        /// To the type with this owner text.
        case type(String)
        /// To its file.
        case file
        /// Nowhere, for this reason.
        case unmapped(String)
    }

    /// Why a span ending past its record is unmapped.
    static let pastRecord = "region extends past its record"

    /// Production records by file.
    private let recordsByFile: [String: [FunctionRecord]]
    /// Types by file.
    private let typesByFile: [String: [TypeRecord]]
    /// Each file's top-level statement lines.
    private let topLevelLines: [String: Set<Int>]
    /// Each file's file-scoped types.
    private let fileScopedTypes: [String: Set<String>]

    /// A placement over `measured`'s production records and its types.
    init(measured: ScanMeasurements) {
        recordsByFile = Dictionary(grouping: measured.records.filter { $0.role == .production }, by: \.file)
        typesByFile = Dictionary(grouping: measured.types, by: \.file)
        topLevelLines = measured.topLevelLines
        fileScopedTypes = measured.fileScopedTypes
    }

    /// Of `elements` whose ranges hold the position, the one starting last,
    /// then ending first, then first by `name`.
    private static func innermost<Element>(
        _ elements: [Element],
        range: KeyPath<Element, SourceSpan>,
        name: KeyPath<Element, String>
    ) -> Element? {
        elements.min { lhs, rhs in
            let left = lhs[keyPath: range]
            let right = rhs[keyPath: range]
            if left.start != right.start {
                return right.start < left.start
            }
            if left.end != right.end {
                return left.end < right.end
            }
            return lhs[keyPath: name] < rhs[keyPath: name]
        }
    }

    /// The production records of `file`.
    func records(in file: String) -> [FunctionRecord] {
        recordsByFile[file] ?? []
    }

    /// The top-level-code record of `file`, if it has one.
    func topLevelRecord(in file: String) -> FunctionRecord? {
        records(in: file).first { $0.kind == .topLevelCode }
    }

    /// The statement lines of `file`'s top-level code.
    func statementLines(in file: String) -> Set<Int> {
        topLevelLines[file] ?? []
    }

    /// The lines `record` spans: its statement lines for top-level code,
    /// else every line of its range.
    func span(of record: FunctionRecord) -> Set<Int> {
        record.kind == .topLevelCode
            ? statementLines(in: record.file)
            : Set(record.range.start.line...record.range.end.line)
    }

    /// Where something of `file` at `position` goes; given `end`, the
    /// position just past its span's last character, a span ending past
    /// its record is unmapped.
    func place(at position: SourcePosition, end: SourcePosition?, in file: String) -> Place {
        let statements = statementLines(in: file)
        let holding = records(in: file).filter { record in
            record.range.contains(position)
                && (record.kind != .topLevelCode || statements.contains(position.line))
        }
        if let record = Self.innermost(holding, range: \.range, name: \.key) {
            guard let end else {
                return .record(record.key)
            }
            let last = SourcePosition(line: end.line, column: end.column - 1)
            return last <= record.range.end ? .record(record.key) : .unmapped(Self.pastRecord)
        }
        let types = (typesByFile[file] ?? []).filter { $0.range.contains(position) }
        if let type = Self.innermost(types, range: \.range, name: \.name) {
            return .type(owner(of: type))
        }
        return .file
    }

    /// The owner text of the innermost type of `file` whose lines hold
    /// `line`; nil when none does.
    func typeOwner(holding line: Int, in file: String) -> String? {
        let types = (typesByFile[file] ?? []).filter { $0.range.start.line <= line && line <= $0.range.end.line }
        return Self.innermost(types, range: \.range, name: \.name).map(owner(of:))
    }

    /// How an attachment names `type`.
    private func owner(of type: TypeRecord) -> String {
        TypeOwner.of(type, fileScopedTypes: fileScopedTypes[type.file] ?? [])
    }
}
