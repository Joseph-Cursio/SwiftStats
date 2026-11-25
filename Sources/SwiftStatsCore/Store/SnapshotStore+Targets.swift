//
//  SnapshotStore+Targets.swift
//  SwiftStatsCore
//
//  A snapshot's executable targets, for test-only production code's entry
//  points (M7, design §8.3): SwiftPM builds `@main` only in an executable
//  target, and the target types are in the stored scan report alone, so
//  only its targets are decoded, each by name and type, and only for a
//  snapshot holding index results, the one signal reading them needs.
//

import Foundation
import GRDB

extension SnapshotStore {
    /// A stored report's target, by name and type.
    private struct StoredTarget: Decodable {
        /// Its name, also its module's.
        let name: String
        /// Its type as SwiftPM describes it.
        let type: String
    }

    /// The part of a stored report naming its targets.
    private struct StoredTargets: Decodable {
        /// The report's targets.
        let targets: [StoredTarget]
    }

    /// The SwiftPM target type of an executable target.
    static let executableType = "executable"

    /// The names of snapshot `id`'s executable targets, from its stored
    /// report, read in `database`; a report that doesn't read throws a
    /// damaged store.
    static func executableTargets(id: Int64, in database: Database) throws -> Set<String> {
        guard let row = try ReportRow.filter(Column("snapshotId") == id).fetchOne(database) else {
            throw StoreError.noSnapshot("id \(id)")
        }
        guard row.encoding == ReportCompression.encoding else {
            throw StoreError.corruptReport("unknown encoding \(row.encoding)")
        }
        let targets: [StoredTarget]
        do {
            let json = try ReportCompression.inflate(row.data, length: row.uncompressedLength)
            targets = try JSONDecoder().decode(StoredTargets.self, from: json).targets
        } catch {
            throw StoreError.corruptReport("the targets of snapshot \(id)")
        }
        return Set(targets.filter { $0.type == executableType }.map(\.name))
    }
}
