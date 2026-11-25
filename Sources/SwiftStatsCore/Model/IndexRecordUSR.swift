//
//  IndexRecordUSR.swift
//  SwiftStatsCore
//
//  A record's USRs from the T1 build's index (M7, design §3): its primary
//  USR, a shorthand subscript's getter USR as its secondary accessor USR,
//  and, for a record with no primary USR, the first reason that applies;
//  for a record with one, whether it is a witness and its referrers
//  (design §4.1), written flat as `witness` and `references`. The scan's
//  `index` block lists every record this way, by key.
//

/// One record's USRs, or why it has none.
public struct IndexRecordUSR: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes.
    private enum CodingKeys: String, CodingKey {
        case key
        case usr
        case usrAccessor
        case reason
        case witness
        case references
    }

    /// The record's key.
    public let key: String
    /// Its primary USR; nil when it has none.
    public let usr: String?
    /// Its secondary accessor USR: a shorthand subscript's getter; nil for
    /// every other record.
    public let usrAccessor: String?
    /// Why it has no primary USR; nil when it has one.
    public let reason: USRReason?
    /// Its witness flag and referrers; nil when it has no primary USR.
    public let coupling: IndexRecordCoupling?

    /// Creates the facts. Fields are documented on their properties.
    public init(
        key: String,
        usr: String?,
        usrAccessor: String?,
        reason: USRReason?,
        coupling: IndexRecordCoupling?
    ) {
        self.key = key
        self.usr = usr
        self.usrAccessor = usrAccessor
        self.reason = reason
        self.coupling = coupling
    }

    /// Reads the facts; it throws for a reason no SwiftStats writes, and
    /// for referrers without a witness flag.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var why: USRReason?
        if let written = try container.decodeIfPresent(String.self, forKey: .reason) {
            why = USRReason(rawValue: written)
            guard why != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .reason,
                    in: container,
                    debugDescription: "no reason \(written)"
                )
            }
        }
        let held = try container.decodeIfPresent(IndexReferences.self, forKey: .references).map { referrers in
            IndexRecordCoupling(witness: try container.decode(Bool.self, forKey: .witness), references: referrers)
        }
        try self.init(
            key: container.decode(String.self, forKey: .key),
            usr: container.decodeIfPresent(String.self, forKey: .usr),
            usrAccessor: container.decodeIfPresent(String.self, forKey: .usrAccessor),
            reason: why,
            coupling: held
        )
    }

    /// Writes the facts, the reason as its raw value, leaving out what the
    /// record doesn't have.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(usr, forKey: .usr)
        try container.encodeIfPresent(usrAccessor, forKey: .usrAccessor)
        try container.encodeIfPresent(reason?.rawValue, forKey: .reason)
        try container.encodeIfPresent(coupling?.witness, forKey: .witness)
        try container.encodeIfPresent(coupling?.references, forKey: .references)
    }
}
