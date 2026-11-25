import Foundation
@testable import SwiftStatsCore
import Testing

/// The inactive #if branch reason needs a read unit (M7, design §3.4, as
/// built after review C9): a record under `#if` with no definition in its
/// range is in an inactive branch only in a file a unit read names; in a
/// file no unit read there are no definitions to find, so the fault
/// reasons (file changed, target not built, file not indexed, unexplained)
/// come first. Synthetic evidence, and the Index fixture's recorded index
/// with `TestOnly.swift`'s unit taken out.
/// Serialized, and each scan runs on a thread of its own: a test holding a
/// pool thread for seconds starves `BlockingAsyncTests`' detached tasks.
@Suite("Inactive #if branch reason", .serialized)
struct InactiveBranchReasonTests {
    @Test("""
        a record under #if with no definition in its range is in an inactive branch only in a file a unit read \
        names: otherwise it reads file changed, target not built, file not indexed or unexplained
        """)
    func inactiveNeedsReadFile() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let flagged = try #require(
            fixture.measured.records.first { $0.ifConfig?.contains("INDEX_FIXTURE_FLAG") == true }
        )
        func reason(changed: Bool, units: EvidenceUnits, compiles: Bool = false) -> USRReason {
            let evidence = USRReasonTests.evidence(
                for: flagged,
                plugin: false,
                definitionInside: false,
                changed: changed,
                units: units
            )
            return USRReason.first(
                for: flagged,
                evidence: USRReason.Evidence(
                    pluginTargets: [],
                    changedFiles: evidence.changedFiles,
                    definitions: [:],
                    unitModules: evidence.unitModules,
                    readFiles: evidence.readFiles,
                    inDisagreement: []
                ) { _ in compiles }
            )
        }
        #expect(reason(changed: false, units: .own) == .inactiveIfBranch)
        #expect(reason(changed: false, units: .absent) == .targetNotBuilt)
        #expect(reason(changed: false, units: .other) == .fileNotIndexed)
        #expect(reason(changed: true, units: .absent) == .fileChanged)
        #expect(reason(changed: false, units: .absent, compiles: true) == .unexplained)
    }

    @Test("""
        a file whose unit was taken out reads file not indexed for every record, its records under #if too: \
        with no unit read for the file, no definition in their ranges is no evidence of an inactive branch
        """)
    func fileNotIndexedUnderIf() async throws {
        var scan = try IndexFixtureScan()
        scan.source = { USRReasonTests.without(["TestOnly.o-"], in: $0) }
        try await scan.run { fixture, outcome in
            let index = try #require(outcome.report.index)
            let file = "Sources/IndexCore/TestOnly.swift"
            let inFile = fixture.measured.records.filter { $0.file == file }
            #expect(inFile.count == 7 && inFile.count { $0.ifConfig != nil } == 3)
            let keys = Set(inFile.map(\.key))
            let reasons = index.records.filter { keys.contains($0.key) }
            #expect(reasons.count == 7)
            #expect(reasons.allSatisfy { $0.usr == nil && $0.reason == .fileNotIndexed })
        }
    }
}
