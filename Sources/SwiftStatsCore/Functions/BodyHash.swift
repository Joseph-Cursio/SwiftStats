//
//  BodyHash.swift
//  SwiftStatsCore
//
//  A short fingerprint of a body's tokens. Comments and whitespace are not
//  tokens, so reformatting or re-commenting a body leaves its hash unchanged;
//  any edit to the code itself changes it. Used to recognise a function that
//  was renamed or moved between snapshots (PRD §6.1).
//

import CryptoKit
import Foundation
import SwiftSyntax

/// Computes body hashes.
enum BodyHash {
    /// Number of leading SHA-256 bytes kept: 8 bytes (16 hex digits) is
    /// plenty to tell apart the bodies of one package.
    private static let keptBytes = 8

    /// The hash of `node`'s token stream, as 16 lowercase hex digits.
    static func of(_ node: some SyntaxProtocol) -> String {
        of(text: CanonicalText.tokenStream(node))
    }

    /// The hash of an already-rendered token stream.
    static func of(text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .prefix(keptBytes)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
