//
//  IndexFamilyReference.swift
//  SwiftStatsCore
//
//  A dependency of one production family on another, from the T1 build's
//  index (M7, design §4.4, for hidden coupling): a record of the first has
//  a counted reference to a record of the second, naming it directly (its
//  USR, or its property's for an accessor) or through a requirement of a
//  package protocol that the record witnesses. Families are named as
//  `FunctionFamily` names them.
//

/// One family's reference to another.
public struct IndexFamilyReference: Codable, Hashable, Sendable {
    /// How the reference reaches the referenced family.
    public enum Via: String, Codable, Sendable {
        /// It names the record's own USR, or its property's.
        case direct
        /// It names a protocol requirement the record witnesses.
        case requirement
    }

    /// The referring family.
    public let fromFamily: String
    /// The referenced family.
    public let toFamily: String
    /// How the reference reaches it.
    public let via: Via

    /// Creates the reference. Fields are documented on their properties.
    public init(fromFamily: String, toFamily: String, via: Via) {
        self.fromFamily = fromFamily
        self.toFamily = toFamily
        self.via = via
    }
}
