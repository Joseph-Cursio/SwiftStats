//
//  PropertyCandidateRow.swift
//  SwiftStatsCore
//
//  The `propertyCandidate` table (store v3, PRD §7.11): one row per
//  SwiftInferProperties candidate, numbered in the report's order, with
//  every field. The location flattens to `file`, `line`, `attachedTo` and
//  `owner`, all null for a candidate with none (a candidate's location has
//  no column); the verify join to `verifyOutcome`, `verifyFresh`,
//  `verified` and `disproven`, all null when the package had no readable
//  verify evidence, and the last three null when the evidence names an
//  interaction row; `testKeys` is newline-joined.
//

import GRDB

/// One property-test candidate in a snapshot.
struct PropertyCandidateRow: Codable, FetchableRecord, PersistableRecord {
    /// The table's columns.
    private enum CodingKeys: String, CodingKey {
        case attachedTo, blocked, decision, disproven, file, function, generated, identity, identityCollision, line
        case ordinal, owner, partner, partnerKey, population, score, scoreBand, site, snapshotId, template
        case testKeys, testedBy, tier, typeName, unmapped, verified, verifyFresh, verifyOutcome
    }

    /// The table name.
    static let databaseTableName = "propertyCandidate"

    /// The snapshot.
    var snapshotId: Int64
    /// The candidate's position in the report, from 0.
    var ordinal: Int
    /// The candidate.
    var candidate: PropertyCandidate

    /// The row for `candidate`, the report's `ordinal`th, in snapshot `snapshotId`.
    init(_ candidate: PropertyCandidate, ordinal: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.ordinal = ordinal
        self.candidate = candidate
    }

    /// Reads a row.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snapshotId = try container.decode(Int64.self, forKey: .snapshotId)
        ordinal = try container.decode(Int.self, forKey: .ordinal)
        let location = try container.decodeIfPresent(FindingTarget.self, forKey: .attachedTo).map { target in
            FindingLocation(
                file: try container.decode(String.self, forKey: .file),
                line: try container.decodeIfPresent(Int.self, forKey: .line),
                column: nil,
                attachedTo: target,
                owner: try container.decodeIfPresent(String.self, forKey: .owner)
            )
        }
        candidate = PropertyCandidate(
            identity: try container.decode(String.self, forKey: .identity),
            population: try container.decode(PropertyCandidate.Population.self, forKey: .population),
            template: try container.decode(String.self, forKey: .template),
            tier: try container.decode(String.self, forKey: .tier),
            score: try container.decode(Int.self, forKey: .score),
            blocked: try container.decode(Bool.self, forKey: .blocked),
            function: try container.decode(String.self, forKey: .function),
            typeName: try container.decodeIfPresent(String.self, forKey: .typeName),
            location: location,
            site: try container.decodeIfPresent(PropertyCandidate.Site.self, forKey: .site),
            unmapped: try container.decodeIfPresent(PropertyCandidate.Unmapped.self, forKey: .unmapped),
            generated: try container.decode(Bool.self, forKey: .generated),
            identityCollision: try container.decode(Bool.self, forKey: .identityCollision),
            partner: try container.decodeIfPresent(String.self, forKey: .partner),
            partnerKey: try container.decodeIfPresent(String.self, forKey: .partnerKey)
        )
        candidate.decision = try container.decodeIfPresent(PropertyCandidate.Decision.self, forKey: .decision)
        candidate.verification = try Self.verification(in: container)
        candidate.testedBy = try container.decodeIfPresent(PropertyCandidate.TestLink.self, forKey: .testedBy)
        candidate.testKeys = try container.decode(String.self, forKey: .testKeys)
            .split(separator: "\n")
            .map(String.init)
    }

    /// The verify join in `container`: nil when its outcome and freshness
    /// are both null, which a joined candidate never has.
    private static func verification(
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> PropertyCandidate.Verification? {
        let outcome = try container.decodeIfPresent(PropertyCandidate.VerifyOutcome.self, forKey: .verifyOutcome)
        let judgement = try container.decodeIfPresent(Bool.self, forKey: .verifyFresh).map { fresh in
            PropertyCandidate.Judgement(
                fresh: fresh,
                verified: try container.decode(Bool.self, forKey: .verified),
                disproven: try container.decode(Bool.self, forKey: .disproven)
            )
        }
        guard outcome != nil || judgement != nil else {
            return nil
        }
        return PropertyCandidate.Verification(outcome: outcome, judgement: judgement)
    }

    /// Writes a row.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(snapshotId, forKey: .snapshotId)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encode(candidate.identity, forKey: .identity)
        try container.encode(candidate.population, forKey: .population)
        try container.encode(candidate.template, forKey: .template)
        try container.encode(candidate.tier, forKey: .tier)
        try container.encode(candidate.score, forKey: .score)
        try container.encode(candidate.scoreBand, forKey: .scoreBand)
        try container.encode(candidate.blocked, forKey: .blocked)
        try container.encode(candidate.function, forKey: .function)
        try container.encodeIfPresent(candidate.typeName, forKey: .typeName)
        try container.encodeIfPresent(candidate.location?.file, forKey: .file)
        try container.encodeIfPresent(candidate.location?.line, forKey: .line)
        try container.encodeIfPresent(candidate.location?.attachedTo, forKey: .attachedTo)
        try container.encodeIfPresent(candidate.location?.owner, forKey: .owner)
        try container.encodeIfPresent(candidate.site, forKey: .site)
        try container.encodeIfPresent(candidate.unmapped, forKey: .unmapped)
        try container.encode(candidate.generated, forKey: .generated)
        try container.encode(candidate.identityCollision, forKey: .identityCollision)
        try container.encodeIfPresent(candidate.partner, forKey: .partner)
        try container.encodeIfPresent(candidate.partnerKey, forKey: .partnerKey)
        try container.encodeIfPresent(candidate.decision, forKey: .decision)
        try container.encodeIfPresent(candidate.verification?.outcome, forKey: .verifyOutcome)
        try container.encodeIfPresent(candidate.verification?.judgement?.fresh, forKey: .verifyFresh)
        try container.encodeIfPresent(candidate.verification?.judgement?.verified, forKey: .verified)
        try container.encodeIfPresent(candidate.verification?.judgement?.disproven, forKey: .disproven)
        try container.encodeIfPresent(candidate.testedBy, forKey: .testedBy)
        try container.encode(candidate.testKeys.joined(separator: "\n"), forKey: .testKeys)
    }
}
