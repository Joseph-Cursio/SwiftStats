import Foundation
import SwiftStatsCore
import Testing

/// PRD M0 done-when (1) and (4): the fixture package covering every function
/// kind scans to the checked-in JSON exactly, and scanning twice gives the
/// same bytes.
///
/// To accept a deliberate change, run with `SWIFTSTATS_UPDATE_GOLDEN=1` and
/// review the diff of `Tests/Fixtures/AllKinds.golden.json`.
@Suite("Golden scan", .serialized)
struct GoldenScanTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private static let package = fixtures.appendingPathComponent("AllKinds")
    private static let golden = fixtures.appendingPathComponent("AllKinds.golden.json")

    private static func scan() throws -> Data {
        try ScanReportEncoder.encode(PackageScanner(tools: .nowhere).scan(packageAt: package))
    }

    @Test("the AllKinds fixture scans to the golden JSON")
    func matchesGolden() throws {
        let actual = try Self.scan()
        if ProcessInfo.processInfo.environment["SWIFTSTATS_UPDATE_GOLDEN"] == "1" {
            try actual.write(to: Self.golden)
        }
        let expected = try Data(contentsOf: Self.golden)
        #expect(
            actual == expected,
            "scan output differs from AllKinds.golden.json; rerun with SWIFTSTATS_UPDATE_GOLDEN=1 and review the diff"
        )
    }

    @Test("two scans of the same tree are byte-identical")
    func deterministic() throws {
        let first = try Self.scan()
        let second = try Self.scan()
        #expect(first == second)
    }

    @Test("a directory without Package.swift is rejected")
    func notAPackage() {
        #expect(throws: ScanError.self) {
            try PackageScanner(tools: .nowhere).scan(packageAt: Self.fixtures)
        }
    }
}
