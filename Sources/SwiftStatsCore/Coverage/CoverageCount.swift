//
//  CoverageCount.swift
//  SwiftStatsCore
//
//  Reads an execution count from llvm-cov's export (M5). Counts are
//  unsigned 64-bit there; every one is read as an integer, never through a
//  floating-point number, and one beyond `Int64.max` is kept as
//  `Int64.max`: saturated, which still reads as covered.
//

/// Execution counts as the export writes them.
enum CoverageCount {
    /// Whether `count` is saturated.
    static func isSaturated(_ count: Int64) -> Bool {
        count == Int64.max
    }

    /// The next count in `container`.
    static func decode(from container: inout any UnkeyedDecodingContainer) throws -> Int64 {
        if let count = try? container.decode(Int64.self) {
            return count
        }
        return Int64(clamping: try container.decode(UInt64.self))
    }

    /// The count under `key` in `container`.
    static func decode<Key: CodingKey>(_ key: Key, from container: KeyedDecodingContainer<Key>) throws -> Int64 {
        if let count = try? container.decode(Int64.self, forKey: key) {
            return count
        }
        return Int64(clamping: try container.decode(UInt64.self, forKey: key))
    }
}
