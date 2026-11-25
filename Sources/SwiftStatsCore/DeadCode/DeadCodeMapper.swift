//
//  DeadCodeMapper.swift
//  SwiftStatsCore
//
//  outskirts' entries mapped onto the scan's records (M7, design §5.4).
//  outskirts lists only the outermost unused declaration and no end
//  position, so the mapping spreads "dead" over SwiftStats' own ranges.
//  Each unused production entry covers records by the first rule that
//  applies (`DeadCodeRules`); anything else covers nothing and is listed
//  where it lies. Entries with another hint, which never make a
//  record dead, are listed and counted but cover nothing, so every covered
//  record is dead in its run. A record covered twice in a run keeps the
//  entry with the lower ordinal. Each run's dead lines come from its
//  maximal covered units (`DeadCodeUnits`).
//

/// Maps outskirts' entries onto a scan.
struct DeadCodeMapper {
    /// The hint of an unused declaration, the only one that makes records
    /// dead.
    static let unusedHint = "unused"
    /// The rule, the `periphery` collector's `map:` option.
    static let rule = "unused production declarations (outskirts lists the outermost): by USR to the record, a "
        + "variable to its property's accessor records (role-free accessorOf), a nominal type to every record it or "
        + "a type nested in it owns in any file (extensions folded, as outskirts folds them; owner by USR with the "
        + "index, else by target, type path and file), an extension to the records in its range, without the index "
        + "a function by its name position; other hints and kinds attached for listing; a record covered twice keeps "
        + "the lower ordinal; dead lines over maximal covered units"

    /// The rules entries are mapped by.
    let rules: DeadCodeRules
    /// Each record's parent record, by key.
    private let parents: [String: String]
    /// Where an entry is listed.
    private let placement: PositionPlacement
    /// Each scanned file's module, by path.
    private let fileModules: [String: String]

    /// A mapper onto `scan`, with `index` when the index ran.
    init(scan: IndexAdapter.Scan, index: DeadCodeIndex?) {
        rules = DeadCodeRules(scan: scan, index: index)
        parents = scan.records.reduce(into: [:]) { parents, record in
            parents[record.key] = record.parentKey
        }
        placement = PositionPlacement(
            records: scan.records,
            types: scan.types,
            topLevelLines: scan.topLevelLines,
            fileScopedTypes: scan.fileScopedTypes,
            roles: .every
        )
        fileModules = Dictionary(scan.files.map { ($0.path, $0.module) }) { first, _ in first }
    }

    /// `output`'s entries mapped: each run's declarations, covered records,
    /// dropped counts and dead lines.
    func report(_ output: PeripheryOutput) -> DeadCodeReport {
        var declarations: [DeadCodeDeclaration] = []
        var records: [DeadCodeRecord] = []
        var dropped: [String: DeadCodeDropped] = [:]
        var deadLines: [String: [String: Int]] = [:]
        for run in DeadCodeRun.ordered {
            let entries = output.entries(of: run).sorted { $0.ordinal < $1.ordinal }
            var units = DeadCodeUnits(parents: parents)
            var covered: [String: DeadCodeRecord] = [:]
            for entry in entries {
                let cover = rules.cover(of: entry)
                declarations.append(declaration(entry, cover: cover))
                if let unit = cover.unit {
                    units.add(unit)
                }
                for key in cover.keys {
                    if let via = cover.via, covered[key] == nil {
                        covered[key] = DeadCodeRecord(key: key, run: run, declaration: entry.ordinal, via: via)
                    }
                    if let record = rules.recordsByKey[key] {
                        units.add(.record(record))
                    }
                }
            }
            records += covered.values.sorted { CodePointOrder.precedes($0.key, $1.key) }
            dropped[run.rawValue] = DeadCodeDropped(entries.map(\.entryClass))
            deadLines[run.rawValue] = units.lines()
        }
        return DeadCodeReport(
            version: output.version,
            runs: DeadCodeRun.ordered.map { DeadCodeRunResults(name: $0, results: output.entries(of: $0).count) },
            declarations: declarations,
            records: records,
            dropped: dropped,
            deadLines: deadLines
        )
    }

    /// `entry` as the scan keeps it, with what it covers.
    private func declaration(_ entry: PeripheryEntry, cover: DeadCodeCover) -> DeadCodeDeclaration {
        let (place, owner) = listing(of: entry)
        return DeadCodeDeclaration(
            run: entry.run,
            ordinal: entry.ordinal,
            hint: entry.hint,
            hintText: entry.hintText,
            kind: entry.kind,
            name: entry.name,
            accessibility: entry.accessibility,
            attributes: entry.attributes,
            modifiers: entry.modifiers,
            ids: entry.ids,
            modules: entry.modules,
            entryClass: entry.entryClass,
            file: entry.file,
            line: entry.line,
            column: entry.column,
            place: place,
            owner: owner,
            module: entry.file.flatMap { fileModules[$0] },
            strippedLines: cover.lines
        )
    }

    /// Where `entry` is listed: `unscanned` outside the scanned files, its
    /// file when the file changed during the scan, else as findings
    /// attach.
    private func listing(of entry: PeripheryEntry) -> (FindingTarget, String?) {
        guard let file = entry.file, fileModules[file] != nil,
              [.build, .outsideRoot, .unscanned].contains(entry.entryClass) == false else {
            return (.unscanned, nil)
        }
        if entry.entryClass == .fileChanged {
            return (.file, nil)
        }
        let position = SourcePosition(line: entry.line, column: entry.column)
        switch placement.place(at: position, end: nil, in: file) {
        case .record(let key):
            return (.function, key)

        case .type(let owner):
            return (.type, owner)

        case .file, .unmapped:
            return (.file, nil)
        }
    }
}
