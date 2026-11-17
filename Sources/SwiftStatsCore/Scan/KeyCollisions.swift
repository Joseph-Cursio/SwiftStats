//
//  KeyCollisions.swift
//  SwiftStatsCore
//
//  Keys are meant to be unique, but code the compiler would reject, or
//  declarations the key doesn't yet tell apart, can collide. Rather than drop
//  a record, colliding keys get the file appended (then the line, then the
//  column), descendants follow their parent's new key, and each collision is
//  reported as a warning.
//

/// Makes record keys unique.
enum KeyCollisions {
    /// Rounds of renaming before giving up: a rename can only collide again
    /// through a descendant whose prefix changed, so a few rounds suffice.
    private static let maximumRounds = 4

    /// `records` with unique keys, plus one warning per original key that
    /// collided.
    static func resolve(_ records: [FunctionRecord]) -> (records: [FunctionRecord], warnings: [ScanWarning]) {
        var state = RenamingState(records: records)
        var collided = Set<String>()
        for _ in 0..<maximumRounds {
            let groups = Dictionary(grouping: records.indices) { state.keys[$0] }.filter { $0.value.count > 1 }
            if groups.isEmpty {
                break
            }
            // A parent's key is a prefix of its children's, so sorted order
            // renames parents first; a child whose prefix has already changed
            // is no longer in its group.
            for (key, group) in groups.sorted(by: { $0.key < $1.key }) {
                let members = group.filter { state.keys[$0] == key }
                guard members.count > 1 else {
                    continue
                }
                collided.insert(key)
                for index in members {
                    state.rename(index, to: key + suffix(for: index, among: members, in: records, key: key))
                }
            }
        }
        let resolved = records.indices.map { index in
            records[index].replacingKeys(key: state.keys[index], parentKey: state.parentKeys[index])
        }
        let warnings = collided.sorted().map { key in
            ScanWarning(file: nil, message: "key shared by several declarations, disambiguated by location: \(key)")
        }
        return (resolved, warnings)
    }

    /// The location suffix that tells `index` apart from the other members:
    /// the file, then `:line` if another member shares the file, then
    /// `:column` if another shares the line too.
    private static func suffix(
        for index: Int,
        among members: [Int],
        in records: [FunctionRecord],
        key: String
    ) -> String {
        let record = records[index]
        let sameFile = members.filter { records[$0].file == record.file }
        let sameLine = sameFile.filter { records[$0].range.start.line == record.range.start.line }
        var suffix = key.contains(" @ ") ? "" : " @ " + record.file
        if sameFile.count > 1 {
            suffix += ":\(record.range.start.line)"
        }
        if sameLine.count > 1 {
            suffix += ":\(record.range.start.column)"
        }
        return suffix
    }
}
