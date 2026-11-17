//
//  KeyCollisions.swift
//  SwiftStatsCore
//
//  Keys are meant to be unique, but code the compiler would reject, or
//  declarations the key doesn't yet tell apart, can collide. Rather than drop
//  a record, colliding keys get the file appended (then the line, if they
//  share a file), children are re-pointed at their parent's new key, and the
//  collision is reported as a warning.
//

/// Makes record keys unique.
enum KeyCollisions {
    /// `records` with unique keys, plus one warning per original key that
    /// collided.
    static func resolve(_ records: [FunctionRecord]) -> (records: [FunctionRecord], warnings: [ScanWarning]) {
        let counts = Dictionary(grouping: records, by: \.key).mapValues(\.count)
        guard counts.values.contains(where: { $0 > 1 }) else {
            return (records, [])
        }

        var renamed: [RecordAddress: String] = [:]
        var result = records.map { record -> FunctionRecord in
            guard counts[record.key, default: 0] > 1 else {
                return record
            }
            let suffix = record.key.contains(" @ ") ? "" : " @ " + record.file
            let fileKey = record.key + suffix
            let siblingsInFile = records.filter { $0.key == record.key && $0.file == record.file }.count
            let newKey = siblingsInFile > 1 ? "\(fileKey):\(record.range.start.line)" : fileKey
            renamed[RecordAddress(file: record.file, key: record.key)] = newKey
            return record.replacingKeys(key: newKey, parentKey: record.parentKey)
        }
        result = result.map { record in
            guard let parent = record.parentKey,
                  let newParent = renamed[RecordAddress(file: record.file, key: parent)] else {
                return record
            }
            return record.replacingKeys(key: record.key, parentKey: newParent)
        }

        let warnings = counts
            .filter { $0.value > 1 }
            .map { key, count in
                ScanWarning(
                    file: nil,
                    message: "key shared by \(count) declarations, disambiguated by location: \(key)"
                )
            }
        return (result, warnings)
    }
}
