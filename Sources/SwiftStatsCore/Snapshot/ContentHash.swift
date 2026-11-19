//
//  ContentHash.swift
//  SwiftStatsCore
//
//  SHA-256 in lowercase hex, for build identities and dirty-tree hashes
//  (PRD §6.2).
//

import CryptoKit
import Foundation

/// SHA-256 digests as hex strings.
enum ContentHash {
    /// The hex digest of `data`.
    static func sha256(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    /// The hex digest of the file at `url`, or nil when it can't be read.
    static func sha256(ofFileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return sha256(data)
    }

    /// `digest` in lowercase hex.
    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
