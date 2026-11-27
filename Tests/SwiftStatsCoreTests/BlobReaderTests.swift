//
//  BlobReaderTests.swift
//  SwiftStatsCoreTests
//
//  The blobs history reads from `git cat-file --batch` output (PRD §7.13):
//  each blob's content by name, a missing name and another object type
//  left out, and a header whose size is negative skipped like any other
//  malformed header rather than trapping.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// `BlobReader.parse`, given `cat-file --batch` output written by hand.
@Suite("Blob reader")
struct BlobReaderTests {
    /// The blobs `parse` reads from `output`, as text by blob name.
    private static func parsed(_ output: String) -> [String: String] {
        BlobReader.parse(Data(output.utf8)).mapValues { data in
            String(bytes: data, encoding: .utf8) ?? ""
        }
    }

    @Test("each blob's content is read by name; a missing name and a tree are left out")
    func wellFormed() {
        let output = """
        aaaa blob 6
        let a

        bbbb missing
        cccc tree 4
        tree
        dddd blob 0


        """

        #expect(Self.parsed(output) == ["aaaa": "let a\n", "dddd": ""])
    }

    @Test("a blob header with a negative size is skipped like a malformed one, and the next blob still reads")
    func negativeBlobSize() {
        let output = "aaaa blob -5\nbbbb blob 3\nxyz\n"

        #expect(Self.parsed(output) == ["bbbb": "xyz"])
    }

    /// Its content isn't kept, but a step of -100 from the end of the
    /// header lands before the output's first byte.
    @Test("another object's header with a negative size is skipped too, not stepped back past the output's start")
    func negativeTreeSize() {
        let output = "aaaa tree -100\nbbbb blob 3\nxyz\n"

        #expect(Self.parsed(output) == ["bbbb": "xyz"])
    }
}
