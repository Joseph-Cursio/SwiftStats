//
//  FindingMapper.swift
//  SwiftStatsCore
//
//  Attaches each place a finding names to the innermost function record
//  whose lines hold it, else the innermost type, else its file, or marks it
//  unscanned (PRD §7.16). A file's top-level-code record holds only its
//  statements' lines, not the declarations between them. A type is named
//  by `TypeOwner`, its file added when it is file-scoped (M5).
//

/// Attaches findings to records, types and files.
struct FindingMapper {
    /// Function records by file.
    private let recordsByFile: [String: [FunctionRecord]]
    /// Types by file.
    private let typesByFile: [String: [TypeRecord]]
    /// Every scanned file.
    private let scannedFiles: Set<String>
    /// Each file's top-level statement lines.
    private let topLevelLines: [String: Set<Int>]
    /// Each file's file-scoped types, as dotted paths.
    private let fileScopedTypes: [String: Set<String>]

    /// A mapper over `measured`'s records, types and files, with each
    /// file's top-level statement lines and file-scoped types.
    init(measured: ScanMeasurements) {
        recordsByFile = Dictionary(grouping: measured.records, by: \.file)
        typesByFile = Dictionary(grouping: measured.types, by: \.file)
        scannedFiles = Set(measured.files.map(\.path))
        topLevelLines = measured.topLevelLines
        fileScopedTypes = measured.fileScopedTypes
    }

    /// `raw` with every place attached, its places in the order given.
    func finding(for raw: RawFinding) -> Finding {
        Finding(
            tool: raw.tool,
            rule: raw.rule,
            category: raw.category,
            kind: raw.kind,
            severity: raw.severity,
            message: raw.message,
            symbol: raw.symbol,
            locations: raw.places.map(location(for:))
        )
    }

    /// Where `place` attaches.
    func location(for place: RawFinding.Place) -> FindingLocation {
        let target: FindingTarget
        let owner: String?
        let statementLines = topLevelLines[place.file] ?? []
        let records = (recordsByFile[place.file] ?? []).filter { record in
            record.kind != .topLevelCode || place.line.map(statementLines.contains) == true
        }
        let types = typesByFile[place.file] ?? []
        if let line = place.line, let record = innermost(records, holding: line, range: \.range) {
            target = .function
            owner = record.key
        } else if let line = place.line, let type = innermost(types, holding: line, range: \.range) {
            target = .type
            owner = TypeOwner.of(type, fileScopedTypes: fileScopedTypes[place.file] ?? [])
        } else {
            target = scannedFiles.contains(place.file) ? .file : .unscanned
            owner = nil
        }
        return FindingLocation(
            file: place.file,
            line: place.line,
            column: place.column,
            attachedTo: target,
            owner: owner
        )
    }

    /// The element whose lines hold `line` and that starts last; among
    /// those starting together, the one that ends first.
    private func innermost<Element>(
        _ elements: [Element],
        holding line: Int,
        range: KeyPath<Element, SourceSpan>
    ) -> Element? {
        elements
            .filter { $0[keyPath: range].start.line <= line && line <= $0[keyPath: range].end.line }
            .min { lhs, rhs in
                let left = lhs[keyPath: range]
                let right = rhs[keyPath: range]
                if left.start != right.start {
                    return right.start < left.start
                }
                return left.end < right.end
            }
    }
}
