import Foundation
@testable import SwiftStatsCore
import Testing

/// Where the dead-code mapping lists an entry it doesn't place on a
/// record (M7, design §5.4): a file changed during the scan lists its
/// entries on the file, and an unscanned file's entry, test code among
/// them, is unscanned. On the Index fixture's measured records, with
/// hand-written entries, no scan run.
extension DeadCodeMappingTests {
    @Test("""
        an entry in a file changed during the scan is listed on its file though it lies in a record, and an \
        unscanned test file's entry is listed as unscanned
        """)
    func listedOutsideRecords() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let package = try IndexWalkHarness.recordedPackage()
        let measured = fixture.measured
        let context = PeripheryOutput.Context(
            root: fixture.root,
            scratch: fixture.build,
            package: package,
            modules: try BuildSession.moduleMap(of: package),
            files: Dictionary(measured.files.map { ($0.path, $0.module) }) { first, _ in first },
            changedFiles: ["Sources/IndexCore/Locals.swift"],
            records: measured.records,
            localUSRs: []
        )
        let data = try PeripheryOutputTests.json(
            ["/Sources/IndexCore/Locals.swift:26:9", "/Tests/IndexCoreTests/Unparsed.swift:1:6"].map { place in
                [
                    "accessibility": "internal", "attributes": [String](), "hints": ["unused"], "ids": ["s:local"],
                    "kind": "function.free", "location": fixture.root + place, "modifiers": [String](),
                    "modules": ["IndexCore"], "name": "f()"
                ]
            }
        )
        let scan = IndexAdapter.Scan(
            root: URL(fileURLWithPath: fixture.root),
            records: measured.records,
            types: measured.types,
            files: measured.files,
            targets: fixture.targets,
            topLevelLines: measured.topLevelLines,
            fileScopedTypes: measured.fileScopedTypes,
            warnings: measured.warnings
        )

        let entries = try PeripheryOutput.decode(data, run: .production, context: context)
        let output = PeripheryOutput(version: "3.28.0", retained: [], entries: entries)
        let listed = DeadCodeMapper(scan: scan, index: nil).report(output).declarations

        #expect(entries.map(\.entryClass) == [.fileChanged, .test])
        #expect(listed.map(\.place) == [.file, .unscanned])
        #expect(listed.map(\.owner) == [nil, nil])
    }
}
