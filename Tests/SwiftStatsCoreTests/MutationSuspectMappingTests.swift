import Foundation
@testable import SwiftStatsCore
import Testing

/// The suspect tests the mapper records for a run (M6, design §2, §3),
/// told apart by name and file as SwiftMutator tells them apart, on the
/// Coverage fixture's recorded run.
@Suite("Mutation mapper suspects")
struct MutationSuspectMappingTests {
    @Test("""
        suspect tests sharing a name are kept apart by their file, each with why it is suspect, as SwiftMutator \
        tells tests apart
        """)
    func suspectsSharingAName() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, _) = try MappingHarness.coverageRun()
        let suspects = SuspectReport(
            flagged: [],
            suspectsChecked: true,
            suspectTests: [
                SuspectReport.SuspectTest(
                    name: "basics()",
                    file: "ATests.swift",
                    reason: .reach,
                    files: 5,
                    filesWithKills: 6
                ),
                SuspectReport.SuspectTest(
                    name: "basics()",
                    file: "BTests.swift",
                    reason: .controlRun,
                    files: nil,
                    filesWithKills: nil
                )
            ],
            unreadableKeys: 0,
            read: true
        )

        let report = harness.report(results, suspects: suspects)

        #expect(report.suspectTests == [
            MutationSuspectTest(
                name: "basics()",
                file: "ATests.swift",
                run: 0,
                why: .reach,
                files: 5,
                filesWithKills: 6
            ),
            MutationSuspectTest(
                name: "basics()",
                file: "BTests.swift",
                run: 0,
                why: .controlRun,
                files: nil,
                filesWithKills: nil
            )
        ])
    }
}
