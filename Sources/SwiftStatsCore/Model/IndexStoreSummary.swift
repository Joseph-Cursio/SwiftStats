//
//  IndexStoreSummary.swift
//  SwiftStatsCore
//
//  What the `index` collector read of the T1 build's index store (M7,
//  design §2.3, §9.2): its layout, its units counted by class, the records
//  read (each once, though several units may name one) and their
//  occurrences, and the listed units.
//

/// The index store as the `index` collector read it.
public struct IndexStoreSummary: Codable, Hashable, Sendable {
    /// The layout of the store the build wrote: always Swift Build's
    /// (`<scratch>/out`).
    public static let swiftBuildLayout = "swiftbuild"

    /// The store's layout.
    public let layout: String
    /// Its units by class, and the quarantined ones.
    public let counts: IndexUnitCounts
    /// The records read: the kept and variant units' records, each once.
    public let records: Int
    /// Their occurrences.
    public let occurrences: Int
    /// The units of every class but `system` and `otherPackage`, by name.
    public let units: [IndexUnitRow]

    /// Creates a summary. Fields are documented on their properties.
    public init(layout: String, counts: IndexUnitCounts, records: Int, occurrences: Int, units: [IndexUnitRow]) {
        self.layout = layout
        self.counts = counts
        self.records = records
        self.occurrences = occurrences
        self.units = units
    }
}
