//
//  USRJoin.swift
//  SwiftStatsCore
//
//  Gives the scan's records their USRs from the T1 build's index (M7,
//  design §3.1–§3.3, §3.5). Every definition occurrence read from a kept
//  or variant unit's record, in a scanned file that didn't change during
//  the scan, is skipped unless its symbol is function-like and explicit
//  (implicit definitions are compiler-made: Swift Testing's peers,
//  synthesized members, stored properties' accessors); otherwise it goes
//  to the innermost record whose stored range holds its line and UTF-8
//  column (the latest start, then the earliest end, then the key), when
//  that record's kind and accessor kind are compatible. A shorthand
//  subscript's getter, defined at the `{`, becomes its subscript record's
//  secondary accessor USR when the subscript has no accessor records and
//  the getter is an accessor of the subscript's USR. A record with several
//  distinct primary USRs keeps none, nor does any record sharing a USR
//  with another; both are listed as disagreements. A definition no record
//  takes is listed apart: a protocol requirement without a body, a kind
//  the innermost record doesn't match, or outside every record.
//
//  A record is read once, but each unit naming it files its occurrences
//  under that unit's main file (two files with one name and the same bytes
//  share a record), and a definition met twice through variant units
//  counts once.
//

/// The scan's records joined to the index's definitions.
struct USRJoin {
    /// A function-like definition read from the index.
    struct Definition: Hashable {
        /// Its file, relative to the package root.
        let file: String
        /// Its line and UTF-8 column.
        let position: SourcePosition
        /// Its occurrence.
        let occurrence: IndexOccurrenceFact

        /// The definition as a listing of `kind`, keyed `key` when a
        /// record is concerned, for `subreason` when it has no record.
        func listing(_ kind: USRListing.Kind, key: String?, subreason: USRListing.Subreason?) -> USRListing {
            USRListing(
                kind: kind,
                subreason: subreason,
                usr: occurrence.usr,
                key: key,
                symbolKind: occurrence.kind,
                name: occurrence.name,
                file: file,
                line: position.line,
                column: position.column
            )
        }
    }

    /// What the definitions of one file give, before disagreements are
    /// settled.
    private struct Assignments {
        /// Each record's distinct primary USRs, with their first
        /// definition.
        var primaries: [String: [String: Definition]] = [:]
        /// Getters whose innermost record is a subscript, with its key.
        var getters: [(definition: Definition, key: String)] = []
        /// Definitions no compatible record takes.
        var withoutRecord: [USRListing] = []
        /// The distinct definitions assigned: file, position and USR.
        var joined: Set<[String]> = []
        /// The distinct implicit function-like definitions skipped.
        var implicit: Set<[String]> = []
        /// Every definition of any kind read, each once, by file.
        var positions: [String: [SourcePosition]] = [:]
    }

    /// The primary USRs once disagreements are settled.
    private struct Settled {
        /// Each record's primary USR, by key.
        var primary: [String: String] = [:]
        /// The definition behind each, by key.
        var definitions: [String: Definition] = [:]
        /// The records in a disagreement, by key.
        var inDisagreement: Set<String> = []
        /// The disagreements' listings.
        var listings: [USRListing] = []
    }

    /// The rule, as the `index` collector's `usr:` option states it.
    static let rule = "non-implicit function-like definitions to the innermost record holding the definition's "
        + "line and UTF-8 column, kind and subkind compatible; a shorthand subscript's getter as its secondary "
        + "accessor USR"

    /// Each record's primary USR, by key, records in a disagreement left
    /// out.
    let primary: [String: String]
    /// The definition behind each primary USR, by key.
    let primaryDefinitions: [String: Definition]
    /// Each shorthand subscript's secondary accessor USR, by key.
    let secondary: [String: String]
    /// The records in a disagreement, by key.
    let inDisagreement: Set<String>
    /// The disagreements, by kind, then key, then USR.
    let disagreements: [USRListing]
    /// The definitions with no record, by file, then position, then USR.
    let withoutRecord: [USRListing]
    /// Every definition of any kind read, implicit ones included, each
    /// once, by file.
    let definitionPositions: [String: [SourcePosition]]
    /// How many distinct definitions were assigned, primary or secondary.
    let joinedCount: Int
    /// How many distinct implicit function-like definitions were skipped.
    let implicitCount: Int
    /// Each unit-read file's occurrences, as `occurrences(in:)` files
    /// them, kept for the coupling so it doesn't file them again.
    let filedOccurrences: [String: [IndexOccurrenceFact]]

    /// The join of `snapshot`'s definitions to `records`, those of `files`
    /// (the scanned files) that aren't among `changedFiles`.
    init(snapshot: IndexSnapshot, records: [FunctionRecord], files: Set<String>, changedFiles: Set<String>) {
        filedOccurrences = Self.occurrences(in: snapshot)
        var assignments = Self.assignments(of: filedOccurrences, to: records, files: files.subtracting(changedFiles))
        let settled = Self.settled(assignments.primaries)
        primary = settled.primary
        primaryDefinitions = settled.definitions
        inDisagreement = settled.inDisagreement
        disagreements = settled.listings
        secondary = Self.secondaries(
            &assignments,
            primary: settled.primary,
            hasAccessors: Set(records.filter { $0.kind == .accessor }.compactMap(\.parentKey))
        )
        withoutRecord = assignments.withoutRecord.sorted { lhs, rhs in
            (lhs.file, lhs.line, lhs.column, lhs.usr ?? "") < (rhs.file, rhs.line, rhs.column, rhs.usr ?? "")
        }
        definitionPositions = assignments.positions
        joinedCount = assignments.joined.count
        implicitCount = assignments.implicit.count
    }

    /// Each unit-read file's occurrences: every record a kept or variant
    /// unit names, filed under the unit's main file when it names that
    /// record alone, else under the record's own file; each record once
    /// per file.
    static func occurrences(in snapshot: IndexSnapshot) -> [String: [IndexOccurrenceFact]] {
        let records = Dictionary(snapshot.records.map { ($0.name, $0) }) { first, _ in first }
        var filed: Set<[String]> = []
        var occurrences: [String: [IndexOccurrenceFact]] = [:]
        for unit in snapshot.readUnits {
            for name in unit.records {
                guard let record = records[name] else {
                    continue
                }
                let file = unit.records.count == 1 && unit.path.isEmpty == false ? unit.path : record.path
                if filed.insert([name, file]).inserted {
                    occurrences[file, default: []].append(contentsOf: record.occurrences)
                }
            }
        }
        return occurrences
    }

    /// What the definitions among `filed` (each file's occurrences, as
    /// `occurrences(in:)` files them) give `records`: each definition met
    /// once (variant units can repeat one), its position noted, and the
    /// function-like ones in `joinable` files (scanned, unchanged)
    /// assigned or set aside.
    private static func assignments(
        of filed: [String: [IndexOccurrenceFact]],
        to records: [FunctionRecord],
        files joinable: Set<String>
    ) -> Assignments {
        let byFile = Dictionary(grouping: records, by: \.file)
        var assignments = Assignments()
        for (file, occurrences) in filed.sorted(by: { $0.key < $1.key }) {
            var seen: Set<[String]> = []
            for occurrence in occurrences where occurrence.roles & IndexSymbolKind.Role.definition != 0 {
                let identity = [
                    "\(occurrence.line)", "\(occurrence.column)", occurrence.usr, "\(occurrence.kind)",
                    "\(occurrence.subkind)", "\(occurrence.roles)"
                ]
                guard seen.insert(identity).inserted else {
                    continue
                }
                let position = SourcePosition(line: occurrence.line, column: occurrence.column)
                assignments.positions[file, default: []].append(position)
                if joinable.contains(file), USRKinds.isFunctionLike(occurrence) {
                    assign(
                        Definition(file: file, position: position, occurrence: occurrence),
                        among: byFile[file, default: []],
                        to: &assignments
                    )
                }
            }
        }
        return assignments
    }

    /// The secondary accessor USRs of `assignments`' getters, by subscript
    /// key: a getter whose subscript has no accessor records (keys in
    /// `hasAccessors` have) and whose `accessorOf` relation names the
    /// subscript's `primary` USR, the first in source order; every other
    /// getter is set aside as an incompatible kind.
    private static func secondaries(
        _ assignments: inout Assignments,
        primary: [String: String],
        hasAccessors: Set<String>
    ) -> [String: String] {
        var secondaries: [String: String] = [:]
        for (definition, key) in assignments.getters.sorted(by: { precedes($0.definition, $1.definition) }) {
            let namesPrimary = definition.occurrence.relations.contains { relation in
                relation.roles & IndexSymbolKind.RelationRole.accessorOf != 0 && relation.usr == primary[key]
            }
            if hasAccessors.contains(key) == false, namesPrimary, secondaries[key] == nil {
                secondaries[key] = definition.occurrence.usr
                assignments.joined.insert([definition.file] + place(of: definition))
            } else {
                assignments.withoutRecord.append(definition.listing(.noRecord, key: key, subreason: .incompatibleKind))
            }
        }
        return secondaries
    }

    /// Assigns `definition` to the innermost compatible record among
    /// `records` (its file's), or notes why none takes it.
    private static func assign(
        _ definition: Definition,
        among records: [FunctionRecord],
        to assignments: inout Assignments
    ) {
        let occurrence = definition.occurrence
        let place = [definition.file] + Self.place(of: definition)
        guard occurrence.roles & IndexSymbolKind.Role.implicit == 0 else {
            assignments.implicit.insert(place)
            return
        }
        guard let record = innermost(of: records, holding: definition.position) else {
            let isRequirement = occurrence.relations.contains { relation in
                relation.roles & IndexSymbolKind.RelationRole.childOf != 0 && relation.kind == IndexSymbolKind.protocol
            }
            assignments.withoutRecord.append(
                definition.listing(.noRecord, key: nil, subreason: isRequirement ? .requirement : .outsideRecords)
            )
            return
        }
        if USRKinds.isCompatible(record, with: occurrence) {
            let held = assignments.primaries[record.key, default: [:]][occurrence.usr]
            if held.map({ precedes(definition, $0) }) ?? true {
                assignments.primaries[record.key, default: [:]][occurrence.usr] = definition
            }
            assignments.joined.insert(place)
        } else if record.kind == .subscriptDeclaration, USRKinds.functionKinds.contains(occurrence.kind),
                  occurrence.subkind == IndexSymbolKind.Subkind.accessorGetter {
            assignments.getters.append((definition, record.key))
        } else {
            assignments.withoutRecord.append(
                definition.listing(.noRecord, key: record.key, subreason: .incompatibleKind)
            )
        }
    }

    /// The innermost of `records` whose range holds `position`: the one
    /// starting last, then ending first, then first by key.
    static func innermost(of records: [FunctionRecord], holding position: SourcePosition) -> FunctionRecord? {
        records.filter { $0.range.contains(position) }.min { lhs, rhs in
            if lhs.range.start != rhs.range.start {
                return rhs.range.start < lhs.range.start
            }
            if lhs.range.end != rhs.range.end {
                return lhs.range.end < rhs.range.end
            }
            return lhs.key < rhs.key
        }
    }

    /// The primary USRs once disagreements take theirs away, the
    /// definitions behind them, the records in a disagreement and its
    /// listings: a record with several USRs (a row per USR), then a USR on
    /// several records (a row per record), each kind by key, then USR.
    private static func settled(_ primaries: [String: [String: Definition]]) -> Settled {
        var holders: [String: Set<String>] = [:]
        for (key, usrs) in primaries {
            for usr in usrs.keys {
                holders[usr, default: []].insert(key)
            }
        }
        var settled = Settled()
        for (key, usrs) in primaries.sorted(by: { $0.key < $1.key }) where usrs.count > 1 {
            settled.inDisagreement.insert(key)
            settled.listings += usrs.sorted { $0.key < $1.key }
                .map { $0.value.listing(.severalUSRs, key: key, subreason: nil) }
        }
        var shared: [USRListing] = []
        for (usr, keys) in holders where keys.count > 1 {
            settled.inDisagreement.formUnion(keys)
            shared += keys.compactMap { key in
                primaries[key]?[usr]?.listing(.sharedUSR, key: key, subreason: nil)
            }
        }
        settled.listings += shared.sorted { lhs, rhs in
            (lhs.key ?? "", lhs.usr ?? "") < (rhs.key ?? "", rhs.usr ?? "")
        }
        for (key, usrs) in primaries where settled.inDisagreement.contains(key) == false {
            if let (usr, definition) = usrs.first {
                settled.primary[key] = usr
                settled.definitions[key] = definition
            }
        }
        return settled
    }

    /// Whether `lhs` comes before `rhs` in source order, then by USR.
    private static func precedes(_ lhs: Definition, _ rhs: Definition) -> Bool {
        (lhs.file, lhs.position.line, lhs.position.column, lhs.occurrence.usr)
            < (rhs.file, rhs.position.line, rhs.position.column, rhs.occurrence.usr)
    }

    /// `definition`'s line, column and USR, as strings, identifying it in
    /// its file.
    private static func place(of definition: Definition) -> [String] {
        ["\(definition.position.line)", "\(definition.position.column)", definition.occurrence.usr]
    }
}
