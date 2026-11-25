//
//  PositionPlacement.swift
//  SwiftStatsCore
//
//  Where something at a position of a kept file goes (M5, M6, M7): coverage
//  places an export entry by the start of its first region, mutation a
//  mutant by its anchor, the build a type-check timing entry by its
//  declaration's name, the dead-code mapping an outskirts entry by its
//  name, for listing. The position, compared by (line, column), goes to
//  the innermost record holding it (the latest start, then the earliest
//  end, then the key; a file's top-level-code record only on its statement
//  lines), else to the innermost type holding it, else to its file. Which
//  records count is the placement's roles: production records only, the
//  default, as coverage and mutation place; or every record, tests and
//  helpers included, as the build's timings place (M7, design §6.2). The
//  timings also ask for the local type holding a position its innermost
//  record holds outside the type's members (`localTypeOwner`).
//  Columns compare as they are: the records count a byte order mark's
//  bytes on line 1, and callers give positions counted the same way. Given
//  an end, a span ending past its record is unmapped.
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

    /// Which records a placement places on.
    enum Roles {
        /// Every record: production code, tests and test helpers.
        case every
        /// Production records only.
        case production
    }

    /// Why a span ending past its record is unmapped.
    static let pastRecord = "region extends past its record"

    /// The records placed on, by file.
    private let recordsByFile: [String: [FunctionRecord]]
    /// Types by file.
    private let typesByFile: [String: [TypeRecord]]
    /// Each file's top-level statement lines.
    private let topLevelLines: [String: Set<Int>]
    /// Each file's file-scoped types.
    private let fileScopedTypes: [String: Set<String>]

    /// A placement over `measured`'s production records and its types, as
    /// coverage and mutation place.
    init(measured: ScanMeasurements) {
        self.init(measured: measured, roles: .production)
    }

    /// A placement over `measured`'s records of `roles` and its types.
    init(measured: ScanMeasurements, roles: Roles) {
        self.init(
            records: measured.records,
            types: measured.types,
            topLevelLines: measured.topLevelLines,
            fileScopedTypes: measured.fileScopedTypes,
            roles: roles
        )
    }

    /// A placement over `records` of `roles` and `types`, each file's
    /// top-level statement lines in `topLevelLines` and its file-scoped
    /// types in `fileScopedTypes`, as the scan measured them.
    init(
        records: [FunctionRecord],
        types: [TypeRecord],
        topLevelLines: [String: Set<Int>],
        fileScopedTypes: [String: Set<String>],
        roles: Roles
    ) {
        let placed = roles == .every ? records : records.filter { $0.role == .production }
        recordsByFile = Dictionary(grouping: placed, by: \.file)
        typesByFile = Dictionary(grouping: types, by: \.file)
        self.topLevelLines = topLevelLines
        self.fileScopedTypes = fileScopedTypes
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

    /// The records of `file` placed on.
    func records(in file: String) -> [FunctionRecord] {
        recordsByFile[file] ?? []
    }

    /// The top-level-code record of `file`, if it has one (top-level code
    /// is production code).
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

    /// The owner text of the innermost type of `file` that holds
    /// `position` and lies inside the record keyed `key`: a local type
    /// holding the position outside its members, when that record is the
    /// innermost holding it; nil when no such type does.
    func localTypeOwner(at position: SourcePosition, inRecord key: String, in file: String) -> String? {
        guard let record = records(in: file).first(where: { $0.key == key }) else {
            return nil
        }
        let types = (typesByFile[file] ?? []).filter { type in
            type.range.contains(position) && record.range.contains(type.range)
        }
        return Self.innermost(types, range: \.range, name: \.name).map(owner(of:))
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
