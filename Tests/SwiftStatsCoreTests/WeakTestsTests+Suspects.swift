//
//  WeakTestsTests+Suspects.swift
//  SwiftStatsCoreTests
//
//  Weak tests' suspect payload (design §7.1, as built): a suspect-only
//  kill is matched to the run's suspect tests by name alone, and the
//  payload carries no file, so same-named tests in different files that
//  are suspect for the same reason show as one entry.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// How weak tests lists the suspect tests behind a suspect-only kill.
extension WeakTestsTests {
    /// Two `flakyTest()`s, in T.swift and U.swift, both flaky in run 0.
    @Test("""
        same-named suspect tests in different files that are suspect for the same reason are listed once, since the \
        payload carries no file
        """)
    func sameNamedSuspects() throws {
        let suspect = MutationSignalHarness.Planted(
            verdict: .killed,
            suspectOnly: JSONFlag(true),
            killedBy: ["flakyTest()"]
        )
        let cleared = MutationSignalHarness.Planted(
            verdict: .killed,
            suspectOnly: JSONFlag(false),
            killedBy: ["exactTest()"]
        )
        let snapshot = try MutationSignalHarness.stored(
            [MutationSignalHarness.covered([suspect, cleared, cleared])],
            MutationSignalHarness.Setup(suspects: ["T.swift", "U.swift"].map { file in
                MutationSuspectTest(
                    name: "flakyTest()",
                    file: file,
                    run: 0,
                    why: .flaky,
                    files: nil,
                    filesWithKills: nil
                )
            })
        )
        let signal = try MutationSignalHarness.signal(.weakTests, of: snapshot)

        let listed = try #require(signal.items.first?.mutation)
        #expect(listed.suspects == [
            SignalItem.Suspect(name: "flakyTest()", why: "flaky", files: nil, filesWithKills: nil)
        ])
    }
}
