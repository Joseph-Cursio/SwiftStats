//
//  LawCheckRow.swift
//  SwiftStatsCore
//
//  The `lawCheck` table (store v3, PRD §7.11): one row per production
//  (type, protocol) pair the kit covers, numbered in the report's order.
//

import GRDB

/// One law-check pair in a snapshot.
struct LawCheckRow: Codable, FetchableRecord, PersistableRecord {
    /// The table's columns.
    private enum CodingKeys: String, CodingKey {
        case evidence, file, generated, implementation, line, ordinal, provenance, snapshotId, state, type
        case protocolName = "protocol"
    }

    /// The table name.
    static let databaseTableName = "lawCheck"

    /// The snapshot.
    var snapshotId: Int64
    /// The pair's position in the report, from 0.
    var ordinal: Int
    /// The type, as `Module::Name`.
    var type: String
    /// The protocol.
    var protocolName: String
    /// How the type comes to conform.
    var provenance: LawCheck.Provenance
    /// Whether its witnesses are written by hand.
    var implementation: LawCheck.Implementation
    /// Whether the package's tests check it.
    var state: LawCheck.State
    /// What shows it suppressed or run.
    var evidence: LawCheck.Evidence?
    /// The file of the declaration that first makes the type conform.
    var file: String
    /// That declaration's first line.
    var line: Int
    /// Whether that file is generated.
    var generated: Bool

    /// The pair this row records.
    var check: LawCheck {
        LawCheck(
            type: type,
            protocolName: protocolName,
            provenance: provenance,
            implementation: implementation,
            state: state,
            evidence: evidence,
            file: file,
            line: line,
            generated: generated
        )
    }

    /// The row for `check`, the report's `ordinal`th pair, in snapshot `snapshotId`.
    init(_ check: LawCheck, ordinal: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.ordinal = ordinal
        type = check.type
        protocolName = check.protocolName
        provenance = check.provenance
        implementation = check.implementation
        state = check.state
        evidence = check.evidence
        file = check.file
        line = check.line
        generated = check.generated
    }
}
