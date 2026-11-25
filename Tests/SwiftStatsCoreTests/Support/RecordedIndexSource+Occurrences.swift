//
//  RecordedIndexSource+Occurrences.swift
//  SwiftStatsCoreTests
//
//  A recording with one record's occurrences edited, for the reference
//  graph's tests (M7, design §4.1): a role taken off an occurrence, or a
//  reference the fixture's source doesn't hold (a recursive call, a nested
//  function calling its parent) added.
//

@testable import SwiftStatsCore

extension RecordedIndexSource {
    /// This recording with the occurrences of each record whose file ends
    /// with `/` + `file` changed by `change`, and `added` appended to them.
    func changingOccurrences(
        inFile file: String,
        adding added: [IndexOccurrenceFact],
        _ change: (IndexOccurrenceFact) -> IndexOccurrenceFact
    ) -> Self {
        let changed = records.values.map { record in
            guard record.file.hasSuffix("/" + file) else {
                return record
            }
            return IndexRecordFact(
                name: record.name,
                file: record.file,
                occurrences: record.occurrences.map(change) + added
            )
        }
        return RecordedIndexSource(units: Array(units.values), records: changed)
    }
}

extension IndexOccurrenceFact {
    /// A call of the function `usr` named `name` at `position`, called by
    /// and contained by `caller` (`Relation.caller`).
    static func call(of usr: String, named name: String, at position: SourcePosition, from caller: Relation) -> Self {
        let roles = IndexSymbolKind.Role.reference | IndexSymbolKind.Role.call
        return IndexOccurrenceFact(
            line: position.line,
            column: position.column,
            roles: roles | caller.roles,
            usr: usr,
            name: name,
            kind: IndexSymbolKind.function,
            subkind: IndexSymbolKind.Subkind.plain,
            properties: 0,
            relations: [caller]
        )
    }

    /// The occurrence with the role bits `removed` taken off.
    func removing(_ removed: UInt64) -> Self {
        IndexOccurrenceFact(
            line: line,
            column: column,
            roles: roles & ~removed,
            usr: usr,
            name: name,
            kind: kind,
            subkind: subkind,
            properties: properties,
            relations: relations
        )
    }
}

extension IndexOccurrenceFact.Relation {
    /// The relation of a call to its caller, the function `usr` named
    /// `name`, local when `isLocal`: called by and contained by it.
    static func caller(_ usr: String, named name: String, isLocal: Bool) -> Self {
        Self(
            roles: IndexSymbolKind.RelationRole.calledBy | IndexSymbolKind.RelationRole.containedBy,
            usr: usr,
            name: name,
            kind: IndexSymbolKind.function,
            subkind: IndexSymbolKind.Subkind.plain,
            properties: isLocal ? IndexSymbolKind.Property.local : 0
        )
    }
}
