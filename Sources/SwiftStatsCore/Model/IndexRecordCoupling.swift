//
//  IndexRecordCoupling.swift
//  SwiftStatsCore
//
//  What the reference graph gives a record with a primary USR (M7, design
//  §4.1): whether it witnesses or overrides something, and its referrers.
//  A record without a primary USR has neither, so `IndexRecordUSR` holds
//  this part as one optional value, written flat as the record's `witness`
//  and `references`.
//

/// A record's witness flag and referrers.
public struct IndexRecordCoupling: Hashable, Sendable {
    /// Whether its USR (for an accessor, its property's; for a subscript's
    /// getter, the subscript's) is the symbol of an occurrence with an
    /// `overrideOf` relation: a protocol witness, a default implementation
    /// or a class override.
    public let witness: Bool
    /// Its referrers.
    public let references: IndexReferences

    /// Creates the facts. Fields are documented on their properties.
    public init(witness: Bool, references: IndexReferences) {
        self.witness = witness
        self.references = references
    }
}
