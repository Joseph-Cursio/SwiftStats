//
//  PropertyJoinTests+Scores.swift
//  SwiftStatsCoreTests
//
//  The verify join at the ends of an `Int`: fresh `measured-bothPass`
//  evidence lifts a row whose score is as large as an `Int` holds, as the
//  true sum with 50 would, instead of trapping, and leaves the smallest
//  score unlifted. The tool's own scores are far from these, so the rows
//  are written by hand.
//

@testable import SwiftStatsCore
import Testing

/// The verify join at the ends of an `Int`: whether 50 added reaches
/// Strong is decided without overflowing.
extension PropertyJoinTests {
    @Test("""
        fresh bothPass evidence verifies a row whose score is the largest an Int holds instead of trapping \
        when 50 is added, and leaves the row with the smallest score unverified
        """)
    func extremeScores() throws {
        let extremes = [
            Row(
                identity: "0x00000000000000B1",
                location: Self.values,
                score: Int.max,
                tier: "Likely",
                fingerprint: "\"FB1\""
            ),
            Row(
                identity: "0x00000000000000B2",
                location: Self.values,
                score: Int.min,
                tier: "Likely",
                fingerprint: "\"FB2\""
            )
        ]
        let records = """
            {"records": [
              {"identityHash": "00000000000000B1", "outcome": "measured-bothPass", "subjectFingerprint": "FB1"},
              {"identityHash": "00000000000000B2", "outcome": "measured-bothPass", "subjectFingerprint": "FB2"}
            ], "schemaVersion": 1}
            """
        let report = try Self.scan([".swiftinfer/verify-evidence.json": records], rows: extremes)
        let properties = try #require(report.properties)
        let byIdentity = Dictionary(uniqueKeysWithValues: properties.candidates.map { ($0.identity, $0) })

        #expect(byIdentity.mapValues(Self.verification) == [
            "0x00000000000000B1": "measured-bothPass true true false",
            "0x00000000000000B2": "measured-bothPass true false false",
            // The reducer invariant has no record, so its judgement is all false.
            "0x00000000000000D1": "none false false false"
        ])
        #expect(byIdentity.mapValues(\.score) == [
            "0x00000000000000B1": Int.max, "0x00000000000000B2": Int.min, "0x00000000000000D1": 30
        ])
        #expect(report.warnings.isEmpty)
    }
}
