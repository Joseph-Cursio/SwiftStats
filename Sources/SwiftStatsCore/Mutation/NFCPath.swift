//
//  NFCPath.swift
//  SwiftStatsCore
//
//  A path as the mutation mapping compares it (M6, design §3): in
//  Unicode's canonical composition (NFC), as SwiftMutator's own report
//  also looks paths up, then byte for byte. Swift's `String` already
//  treats canonically equivalent spellings as equal, so a `String` key
//  would hide whether the normalisation happens at all, and would fold two
//  files whose names differ only in their bytes without saying so; this
//  key does the normalisation itself and compares exactly what it made.
//

import Foundation

/// A path in NFC, compared by its UTF-8 bytes.
struct NFCPath: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The path in NFC.
    let spelling: String
    /// Its UTF-8 bytes, which equality, hashing and order compare.
    private let bytes: [UInt8]

    /// The path in NFC.
    var description: String {
        spelling
    }

    /// `path` in NFC.
    init(_ path: String) {
        spelling = path.precomposedStringWithCanonicalMapping
        bytes = Array(spelling.utf8)
    }

    /// Whether `lhs` and `rhs` are the same bytes in NFC.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bytes == rhs.bytes
    }

    /// Whether `lhs`'s bytes sort before `rhs`'s: Unicode scalar order,
    /// as `String` orders paths in NFC.
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }

    /// Hashes the bytes.
    func hash(into hasher: inout Hasher) {
        hasher.combine(bytes)
    }
}
