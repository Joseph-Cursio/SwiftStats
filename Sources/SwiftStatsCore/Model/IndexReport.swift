//
//  IndexReport.swift
//  SwiftStatsCore
//
//  What the `index` collector read from the T1 build's index store, mapped
//  onto the scan (M7, design §2, §3, §9.2): the store's units by class and
//  the listed units, the library-product targets it compiled, every
//  record's USRs or the reason it has none, the definitions the join
//  counted, the disagreements, the definitions with no record, the
//  collisions the USR tells apart, and every scanned file hashed after the
//  build. Absent when the collector didn't run.
//

/// A snapshot's index results, mapped to records.
public struct IndexReport: Codable, Hashable, Sendable {
    /// The store as read.
    public let store: IndexStoreSummary
    /// The library-product targets with units read, sorted.
    public let libraryModules: [String]
    /// Every record's USRs, in the scan's record order.
    public let records: [IndexRecordUSR]
    /// What the join counted.
    public let definitions: IndexDefinitions
    /// Records with several primary USRs and USRs on several records, by
    /// kind, then key, then USR.
    public let disagreements: [USRListing]
    /// Definitions with no record, by file, then position, then USR.
    public let withoutRecord: [USRListing]
    /// The records of key collisions their USRs tell apart, by key.
    public let collisions: [USRListing]
    /// Every scanned file, hashed after the build, by path.
    public let files: [IndexFileHash]

    /// Creates a report. Fields are documented on their properties.
    public init(
        store: IndexStoreSummary,
        libraryModules: [String],
        records: [IndexRecordUSR],
        definitions: IndexDefinitions,
        disagreements: [USRListing],
        withoutRecord: [USRListing],
        collisions: [USRListing],
        files: [IndexFileHash]
    ) {
        self.store = store
        self.libraryModules = libraryModules
        self.records = records
        self.definitions = definitions
        self.disagreements = disagreements
        self.withoutRecord = withoutRecord
        self.collisions = collisions
        self.files = files
    }
}
