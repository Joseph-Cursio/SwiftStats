//
//  CoveragePlacement.swift
//  SwiftStatsCore
//
//  Where a coverage export entry of a kept file goes (M5): by the start of
//  its first region, the anchor, compared by (line, column), to the
//  innermost record holding it (the latest start, then the earliest end;
//  a file's top-level-code record only on its statement lines), else to the
//  innermost type holding it, else to its file. Columns compare as they
//  are: the compiler and the records both count a byte order mark's bytes
//  on line 1. An entry whose first region ends past its record is
//  unmapped.
//

/// Places export entries on records, types and files.
struct CoveragePlacement {
    /// Where an entry goes.
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

    /// Why an entry whose first region ends past its record is unmapped.
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

    /// Where an entry of `file` whose first region is `anchor` goes.
    func place(_ anchor: CoverageRegion, in file: String) -> Place {
        let statements = statementLines(in: file)
        let holding = records(in: file).filter { record in
            record.range.contains(anchor.start)
                && (record.kind != .topLevelCode || statements.contains(anchor.start.line))
        }
        if let record = Self.innermost(holding, range: \.range, name: \.key) {
            let last = SourcePosition(line: anchor.end.line, column: anchor.end.column - 1)
            return last <= record.range.end ? .record(record.key) : .unmapped(Self.pastRecord)
        }
        let types = (typesByFile[file] ?? []).filter { $0.range.contains(anchor.start) }
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
