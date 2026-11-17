//
//  RenamingState.swift
//  SwiftStatsCore
//
//  Current keys during collision resolution, and which record is whose
//  parent. Parents are found by identity — same file, the parent's original
//  key, and a range enclosing the child — never by key alone, because two
//  colliding parents in one file share a key.
//

/// Keys being renamed, with each record's parent fixed up front.
struct RenamingState {
    /// Each record's current key.
    private(set) var keys: [String]
    /// Each record's current parent key.
    private(set) var parentKeys: [String?]
    /// Each record's direct children, by index.
    private let children: [Int: [Int]]

    /// Starts from the records' own keys.
    init(records: [FunctionRecord]) {
        keys = records.map(\.key)
        parentKeys = records.map(\.parentKey)

        let byAddress = Dictionary(grouping: records.indices) { index in
            RecordAddress(file: records[index].file, key: records[index].key)
        }
        var childrenByParent: [Int: [Int]] = [:]
        for index in records.indices {
            let record = records[index]
            guard let parentKey = record.parentKey,
                  let candidates = byAddress[RecordAddress(file: record.file, key: parentKey)] else {
                continue
            }
            // The innermost candidate whose range encloses the child.
            let parent = candidates
                .filter { records[$0].range.contains(record.range.start) && $0 != index }
                .max { records[$0].range.start < records[$1].range.start }
            if let parent {
                childrenByParent[parent, default: []].append(index)
            }
        }
        children = childrenByParent
    }

    /// Gives record `index` a new key and carries the change to its
    /// descendants: their parent key, and the prefix of their own key.
    mutating func rename(_ index: Int, to newKey: String) {
        let oldKey = keys[index]
        keys[index] = newKey
        for child in children[index] ?? [] {
            parentKeys[child] = newKey
            let prefix = oldKey + " / "
            if keys[child].hasPrefix(prefix) {
                rename(child, to: newKey + " / " + keys[child].dropFirst(prefix.count))
            }
        }
    }
}
