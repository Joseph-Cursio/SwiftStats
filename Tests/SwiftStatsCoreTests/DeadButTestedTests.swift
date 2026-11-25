//
//  DeadButTestedTests.swift
//  SwiftStatsCoreTests
//
//  Dead but tested's judgement of one function (M7, design §8.2), on
//  hand-made facts: what a mutant that ran is with coverage on and off;
//  the first verdict that applies, a mutant that ran before a file
//  without full results, coverage off's survivors before not covered
//  before build errors; and which run judges a record's mutants (its
//  file's, else each mutant's own) and decides its coverage setting (its
//  file's, else the one its mutants share, else unknown), paths compared
//  in NFC.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Dead but tested's judgement of one function, on hand-made facts.
@Suite("Dead but tested judgement")
struct DeadButTestedTests {
    /// The file the hand-made records lie in, in NFC.
    private static let file = "Sources/Lib/Caf\u{E9}.swift"
    /// The same file in NFD, as SwiftMutator may write it.
    private static let decomposed = "Sources/Lib/Cafe\u{301}.swift"

    /// Counts with `killed`, `survived`, `timedOut`, `noCoverage`,
    /// `notCovered` and `buildErrors` mutants.
    private static func counts(
        killed: Int = 0,
        survived: Int = 0,
        timedOut: Int = 0,
        noCoverage: Int = 0,
        notCovered: Int = 0,
        buildErrors: Int = 0
    ) -> MutationCounts {
        MutationCounts(
            killed: killed,
            crashKills: 0,
            survived: survived,
            noCoverage: noCoverage,
            timedOut: timedOut,
            notCovered: notCovered,
            buildErrors: buildErrors,
            suspectOnly: 0,
            judgedKills: killed
        )
    }

    /// Facts of a record with `counts` (none when nil), all from one run
    /// with coverage off when `off`, in a file of `disposition`.
    private static func facts(
        _ counts: MutationCounts?,
        off: Bool = false,
        disposition: MutationFileDisposition? = .tested
    ) -> MutantsRan.Facts {
        MutantsRan.Facts(
            counts: counts,
            unchecked: off ? (counts?.survived ?? 0) + (counts?.timedOut ?? 0) : 0,
            coverage: off ? .disabled : .enabled,
            disposition: disposition
        )
    }

    /// `verdict` mutants of `owner` in `path` from run `run`.
    private static func mutants(
        _ count: Int,
        _ verdict: MutationVerdict,
        owner: String,
        path: String,
        run: Int
    ) throws -> [Mutant] {
        try (0..<count).map { offset in
            let planted = MutationSignalHarness.Planted(verdict: verdict)
            var row = MutantRow(
                MutationSignalHarness.mutant(planted, path: path, line: 1, column: 1 + offset, owner: owner),
                ordinal: 0,
                snapshotId: 0
            )
            row.run = run
            return try row.mutant
        }
    }

    @Test("""
        a mutant ran when killed, survived or timed out; with coverage off only a kill shows it ran
        """)
    func ran() {
        let mixed = Self.counts(killed: 2, survived: 3, timedOut: 1, noCoverage: 4, notCovered: 5, buildErrors: 6)

        #expect(Self.facts(mixed).ran == 6)
        #expect(Self.facts(mixed, off: true).ran == 2)
        #expect(Self.facts(nil).ran == 0)
        #expect(Self.facts(Self.counts(survived: 1), off: true).ran == 0)
    }

    @Test("""
        the first verdict applies: used, listed (before a file without full results), unresolved or unlisted, \
        no mutant, coverage off's survivors, not covered or no coverage, build errors
        """)
    func verdicts() {
        let verdict = { (dead: Bool, facts: MutantsRan.Facts) in DeadButTested.verdict(dead: dead, facts: facts) }
        let killed = Self.counts(killed: 1)

        #expect(verdict(false, Self.facts(killed)) == .used)
        #expect(verdict(true, Self.facts(killed)) == .listed)
        #expect(verdict(true, Self.facts(Self.counts(timedOut: 1))) == .listed)
        #expect(verdict(true, Self.facts(killed, disposition: .unlisted)) == .listed)
        #expect(verdict(true, Self.facts(nil, disposition: .unlisted)) == .partialResults)
        #expect(verdict(true, Self.facts(Self.counts(notCovered: 1), disposition: .unresolved)) == .partialResults)
        #expect(verdict(true, Self.facts(nil)) == .noMutant)
        #expect(verdict(true, Self.facts(nil, disposition: nil)) == .noMutant)
        #expect(verdict(true, Self.facts(Self.counts(survived: 1, notCovered: 1), off: true)) == .unchecked)
        #expect(verdict(true, Self.facts(Self.counts(timedOut: 1), off: true)) == .unchecked)
        #expect(verdict(true, Self.facts(Self.counts(noCoverage: 1, buildErrors: 1))) == .notCovered)
        #expect(verdict(true, Self.facts(Self.counts(notCovered: 2), off: true)) == .notCovered)
        let unknown = MutantsRan.Facts(
            counts: Self.counts(survived: 2, notCovered: 1),
            unchecked: 1,
            coverage: nil,
            disposition: .unlisted
        )
        #expect(verdict(true, unknown) == .listed)
        let offOnly = MutantsRan.Facts(counts: unknown.counts, unchecked: 2, coverage: nil, disposition: nil)
        #expect(verdict(true, offOnly) == .unchecked)
        #expect(verdict(true, Self.facts(Self.counts(buildErrors: 2))) == .buildErrors)
        #expect(verdict(true, Self.facts(Self.counts())) == .noMutant)
    }

    @Test("""
        a record's mutants are judged by its file's run, else each by its own; its coverage setting is its file's \
        run's, else the one its mutants' runs share, else unknown; its file is found in NFC; a record without \
        mutants counts none
        """)
    func runs() throws {
        let owner = "Lib::func f() -> Int"
        let other = "Lib::func g() -> Int"
        let third = "Lib::func k() -> Int"
        let mutants = try Self.mutants(1, .survived, owner: owner, path: Self.decomposed, run: 1)
            + Self.mutants(1, .survived, owner: other, path: Self.decomposed, run: 0)
            + Self.mutants(1, .killed, owner: other, path: Self.decomposed, run: 1)
            + Self.mutants(1, .survived, owner: third, path: Self.decomposed, run: 1)
            + Self.mutants(1, .killed, owner: third, path: Self.decomposed, run: 0)
        let report = { (fileRun: Int?) in
            MutationReport(
                collectedAt: "2026-11-24T09:00:00.000Z",
                complete: true,
                listsNotCovered: true,
                mode: .full,
                base: nil,
                files: [
                    MutationFile(
                        path: Self.decomposed,
                        sha256: "abc",
                        disposition: .unlisted,
                        changedTest: false,
                        run: fileRun
                    )
                ],
                runs: [IndexHarness.run(0, skipCoverage: false), IndexHarness.run(1, skipCoverage: true)],
                suspectTests: [],
                mutants: mutants
            )
        }

        let named = MutantsRan(report(0)).facts(key: owner, path: Self.file)
        #expect(named.coverage == .enabled && named.disposition == .unlisted && named.ran == 1)
        let shared = MutantsRan(report(nil)).facts(key: owner, path: Self.file)
        #expect(shared.coverage == .disabled && shared.ran == 0 && shared.unchecked == 1)
        let mixed = MutantsRan(report(nil)).facts(key: other, path: Self.file)
        #expect(mixed.coverage == nil && mixed.ran == 2 && mixed.unchecked == 0)
        let survivorOff = MutantsRan(report(nil)).facts(key: third, path: Self.file)
        #expect(survivorOff.coverage == nil && survivorOff.ran == 1 && survivorOff.unchecked == 1)
        #expect(MutantsRan(report(0)).facts(key: third, path: Self.file).ran == 2)
        let fileOff = MutantsRan(report(1)).facts(key: other, path: Self.file)
        #expect(fileOff.coverage == .disabled && fileOff.ran == 1)
        let none = MutantsRan(report(1)).facts(key: "Lib::func h()", path: "Sources/Lib/Other.swift")
        #expect(none.counts == nil && none.disposition == nil && none.coverage == nil && none.ran == 0)
    }
}
