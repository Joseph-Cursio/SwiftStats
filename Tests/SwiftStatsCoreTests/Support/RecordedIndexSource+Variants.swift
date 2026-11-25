//
//  RecordedIndexSource+Variants.swift
//  SwiftStatsCoreTests
//
//  A recording with units of another triple added beside some of its
//  units, for the USR join's variant tests (M7, design §2.3, §3.1): each
//  copy is a variant of its file, naming the original's record or a copy
//  of it under another record name.
//

@testable import SwiftStatsCore

extension RecordedIndexSource {
    /// This recording with a unit `<stem>.o-VARIANT` for triple
    /// `x86_64-apple-macos14.0` beside each unit named `<stem>.o-…` for a
    /// stem in `stems`; the copies of stems in `ownRecords` name a copy of
    /// the original's record, `<stem>.swift-VARIANTREC`, holding the same
    /// definitions, and the others name the original's record.
    func addingVariants(of stems: Set<String>, ownRecords: Set<String>) -> Self {
        var addedUnits: [IndexUnitFact] = []
        var addedRecords: [IndexRecordFact] = []
        for unit in units.values.sorted(by: { $0.name < $1.name }) {
            let stem = String(unit.name.prefix { $0 != "." })
            guard stems.contains(stem) else {
                continue
            }
            var copy = unit.named("\(stem).o-VARIANT").forTriple("x86_64-apple-macos14.0")
            if ownRecords.contains(stem), let name = unit.records.first, let record = records[name] {
                let renamed = "\(stem).swift-VARIANTREC"
                addedRecords.append(IndexRecordFact(name: renamed, file: record.file, occurrences: record.occurrences))
                copy = copy.writing([renamed])
            }
            addedUnits.append(copy)
        }
        return RecordedIndexSource(
            units: Array(units.values) + addedUnits,
            records: Array(records.values) + addedRecords
        )
    }
}
