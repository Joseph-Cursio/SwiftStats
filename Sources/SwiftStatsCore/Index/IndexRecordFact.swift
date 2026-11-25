//
//  IndexRecordFact.swift
//  SwiftStatsCore
//
//  One record of an index store as an `IndexStoreSource` gives it (M7,
//  design §2.2): the occurrences one compile found in one source file.
//  Several units can name one record (the same file compiled twice into
//  identical records). Its coding keys are those of
//  `Scripts/index-check.py dump`; a dump's `otherFiles`, the further paths
//  units give one record, is not kept.
//

/// One record of an index store, copied out of the reader.
struct IndexRecordFact: Decodable, Hashable, Sendable {
    /// The record's name, its file name in `v5/records`.
    let name: String
    /// The source file's absolute real path in NFC, as the units naming
    /// the record give it.
    let file: String
    /// Every occurrence in the record.
    let occurrences: [IndexOccurrenceFact]
}
