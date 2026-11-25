//
//  USRJoin+Collisions.swift
//  SwiftStatsCore
//
//  The key collisions a USR tells apart (M7, design §3.5): when two
//  declarations share a key, `KeyCollisions` appends a location suffix to
//  each (` @ file`, then `:line`, then `:column`) and warns once per key.
//  Those records whose primary USRs differ are listed, each with its USR;
//  informative, never a disagreement.
//

extension USRJoin {
    /// The keys `KeyCollisions` can give `record` for the collided key
    /// `original`: the file appended (unless the key already names one),
    /// then the start line, then the start column.
    private static func suffixed(_ original: String, for record: FunctionRecord) -> Set<String> {
        let withFile = original + (original.contains(" @ ") ? "" : " @ " + record.file)
        let withLine = withFile + ":\(record.range.start.line)"
        return [withFile, withLine, withLine + ":\(record.range.start.column)"]
    }

    /// The records of the collisions `warnings` name among `records` whose
    /// primary USRs differ, each with its USR, by key.
    func collisions(records: [FunctionRecord], warnings: [ScanWarning]) -> [USRListing] {
        let collided = Set(
            warnings.filter { $0.file == nil && $0.message.hasPrefix(KeyCollisions.warningLead) }
                .map { String($0.message.dropFirst(KeyCollisions.warningLead.count)) }
        )
        return collided.sorted().flatMap { original -> [USRListing] in
            let members = records.filter { Self.suffixed(original, for: $0).contains($0.key) }
                .sorted { $0.key < $1.key }
            guard Set(members.compactMap { primary[$0.key] }).count > 1 else {
                return []
            }
            return members.compactMap { record in
                primaryDefinitions[record.key]?.listing(.collision, key: record.key, subreason: nil)
            }
        }
    }
}
