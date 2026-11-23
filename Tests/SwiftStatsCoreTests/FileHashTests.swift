import Foundation
@testable import SwiftStatsCore
import Testing

/// Each scanned file's SHA-256 (M6, design §3): the hash of its bytes as
/// read, before decoding drops a UTF-8 byte order mark, in lowercase hex,
/// as SwiftMutator records `fileSHA256`; the expected digests come from
/// `shasum -a 256` on the same bytes.
@Suite("File hash")
struct FileHashTests {
    @Test("a file's SHA-256 is that of its bytes, a byte order mark included, as shasum -a 256 gives it")
    func rawBytes() throws {
        let bomText = "public func one() -> Int { 1 }\n"
        let package = try TemporaryPackage([
            "Sources/Lib/Bom.swift": "\u{FEFF}" + bomText,
            "Sources/Lib/Plain.swift": "public func two() -> Int { 2 }\n"
        ])
        defer { package.remove() }

        let files = try package.scan(tools: SnapshotHarness.noTools).files
        let hashes = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.sha256) })

        #expect(hashes == [
            "Sources/Lib/Bom.swift": "03c17aaf79561050f9652551eb1e77a8d4701946bd001e4a09bc942a63380a2a",
            "Sources/Lib/Plain.swift": "6a56a7968338aeffc1d6f2518bf20b0aa76c8bf38f10fee5cdc87b668f42fdc7"
        ])
        #expect(hashes["Sources/Lib/Bom.swift"] != ContentHash.sha256(Data(bomText.utf8)))
    }

    @Test("the scan JSON lists each file's SHA-256")
    func encoded() throws {
        let package = try TemporaryPackage(["Sources/Lib/Plain.swift": "public func two() -> Int { 2 }\n"])
        defer { package.remove() }

        let json = try ScanReportEncoder.encode(try package.scan(tools: SnapshotHarness.noTools))
        let text = try #require(String(data: json, encoding: .utf8))

        #expect(text.contains("\"sha256\" : \"6a56a7968338aeffc1d6f2518bf20b0aa76c8bf38f10fee5cdc87b668f42fdc7\""))
    }
}
