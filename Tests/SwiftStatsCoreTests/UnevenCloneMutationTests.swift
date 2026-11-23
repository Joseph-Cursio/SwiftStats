//
//  UnevenCloneMutationTests.swift
//  SwiftStatsCoreTests
//
//  Uneven clone testing, mutation part (PRD §8, M6, design §7.4): which
//  classes are listed, their scores, subjects and copies, the 80% and 20%
//  bounds and the fewest scored mutants, the copies skipped by reason
//  (generated files, files without full results, too few mutants), a
//  copy's mutants found by anchor, by line and column (a mutant
//  SwiftMutator points past the copy's last statement counts; any owner
//  counts; unmapped ones don't; in UnevenCloneMutationTests+Anchors),
//  classes whose poor copies ran unchecked mutants first, folding, the
//  mutants more than one item counts, the limits a configuration sets, and
//  the reasons it is left out.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Uneven clone testing (mutation)")
struct UnevenCloneMutationTests {
    /// The functions file.
    private static let file = UnevenHarness.file

    /// The lines of function `index`.
    private static func lines(_ index: Int) -> ClosedRange<Int> {
        UnevenHarness.lines(of: index)
    }

    /// A class of `mass` found by `run` with a copy over each of `ranges`
    /// of the functions file.
    private static func clone(_ run: String, mass: Int, _ ranges: [ClosedRange<Int>]) -> FakeClone {
        FakeClone(run: run, mass: mass, spans: ranges.map { (Self.file, $0) })
    }

    /// The signal of `setup` with the default limits.
    private static func signal(_ setup: CloneMutationHarness.Setup) throws -> SignalResult {
        try MutationSignalHarness.signal(.unevenCloneMutation, of: try CloneMutationHarness.stored(setup))
    }

    /// `count` mutants with `verdict` in function `index` of the functions
    /// file.
    private static func mutants(_ count: Int, _ verdict: MutationVerdict, _ index: Int) -> [Mutant] {
        CloneMutationHarness.mutants(count, verdict, function: index)
    }

    /// The ordinal of the class of `mass` in `snapshot`.
    private static func ordinal(mass: Int, in snapshot: StoredSnapshot) -> Int? {
        snapshot.cloneClasses.first { $0.mass == mass }?.ordinal
    }

    @Test("""
        a class with a copy at least 80% and one at most 20% killed is listed by its least killed copy, classes \
        whose poor copies ran unchecked mutants first
        """)
    func listing() throws {
        let setup = CloneMutationHarness.Setup(
            files: [Self.file: UnevenHarness.functions(6)],
            clones: [
                Self.clone("default", mass: 40, [Self.lines(0), Self.lines(1)]),
                Self.clone("default", mass: 30, [Self.lines(2), Self.lines(3)]),
                // 50% and 0%: no copy is well tested.
                Self.clone("--sequence", mass: 20, [Self.lines(4), Self.lines(5)])
            ],
            mutants: Self.mutants(3, .killed, 0) + Self.mutants(3, .survived, 1)
                + Self.mutants(4, .killed, 2) + Self.mutants(4, .notCovered, 3)
                + Self.mutants(1, .killed, 4) + Self.mutants(1, .survived, 4) + Self.mutants(2, .noCoverage, 5)
        )

        let signal = try Self.signal(setup)

        #expect(signal.leftOut == nil)
        #expect(signal.candidates == 3)
        // The class whose poor copy ran unchecked mutants comes first, though
        // its score is lower.
        #expect(signal.items.map(\.subject) == [UnevenHarness.key(1), UnevenHarness.key(3)])
        #expect(signal.items.map(\.score) == [3, 4])
        #expect(signal.items.map(\.file) == [Self.file, Self.file] && signal.items.map(\.line) == [6, 16])
        let first = try #require(signal.items.first?.clone)
        #expect(first.mass == 40 && first.copies == 2 && first.lines == 4 && first.coverage == nil)
        #expect(first.mutation?.folded.isEmpty == true)
        let copies = first.mutation?.copies ?? []
        #expect(copies.map(\.file) == [Self.file, Self.file])
        #expect(copies.map(\.family) == [UnevenHarness.key(0), UnevenHarness.key(1)])
        #expect(copies.map { [$0.line, $0.killed, $0.scored, $0.runButUnchecked, $0.unrun] }
            == [[1, 3, 3, 0, 0], [6, 0, 3, 3, 0]])
        let unrun = signal.items.last?.clone?.mutation?.copies.last
        #expect(unrun.map { [$0.line, $0.killed, $0.scored, $0.runButUnchecked, $0.unrun] } == [16, 0, 4, 0, 4])
        #expect(signal.rule == UnevenCloneMutation.rule(thresholds: SignalThresholds()) + "; 6 copies of 3 classes = "
            + "0 in generated files + 0 in files without full results (unresolved or unlisted) + 0 with fewer than 2 "
            + "scored mutants + 6 measured; 3 = 3 with at least 2 measured copies + 0 with fewer; 3 = 2 with a copy "
            + "at least 80% and one at most 20% killed + 1 without; 2 = 2 listed + 0 folded into a listed class; 2 = "
            + "1 with a mutant that ran and wasn't checked + 1 unkilled only through code no test ran (the same "
            + "evidence as uneven clone testing's coverage part); 0 mutants counted by more than one item")
        #expect(MutationSignalHarness.unbalanced(signal.rule).isEmpty)
        #expect(UnevenCloneMutation.rule(thresholds: SignalThresholds()) == "clone classes with a copy at least 80% "
            + "and a copy at most 20% of its mutants killed (code no test ran counting as unkilled), copies with at "
            + "least 2 scored mutants (build errors aside); scored by the unkilled mutants of the copies at most 20% "
            + "killed; classes whose poorly tested copies hold a mutant that ran and wasn't checked come first")
    }

    /// Copies exactly 80% and 20% killed count as well and poorly tested;
    /// copies just short of either bound don't; a copy with one scored
    /// mutant isn't measured. Limits a configuration sets move all three.
    @Test("the 80% and 20% bounds are inclusive, a copy needs 2 scored mutants, and configured limits move both")
    func bounds() throws {
        let setup = CloneMutationHarness.Setup(
            files: [Self.file: UnevenHarness.functions(8)],
            clones: [
                // 4/5 and 1/5: exactly 80% and 20%.
                Self.clone("default", mass: 50, [Self.lines(0), Self.lines(1)]),
                // 7/9 (77.8%) and 0/9: no copy is well tested.
                Self.clone("default", mass: 40, [Self.lines(2), Self.lines(3)]),
                // 9/9 and 2/9 (22.2%): no copy is poorly tested.
                Self.clone("default", mass: 30, [Self.lines(4), Self.lines(5)]),
                // 1/1 has one scored mutant: one measured copy.
                Self.clone("default", mass: 20, [Self.lines(6), Self.lines(7)])
            ],
            mutants: Self.mutants(4, .killed, 0) + Self.mutants(1, .survived, 0)
                + Self.mutants(1, .killed, 1) + Self.mutants(4, .timedOut, 1)
                + Self.mutants(7, .killed, 2) + Self.mutants(2, .survived, 2) + Self.mutants(9, .survived, 3)
                + Self.mutants(9, .killed, 4) + Self.mutants(2, .killed, 5) + Self.mutants(7, .survived, 5)
                + Self.mutants(1, .killed, 6) + Self.mutants(2, .buildError, 6) + Self.mutants(2, .notCovered, 7)
        )
        let snapshot = try CloneMutationHarness.stored(setup)
        let loose = SignalThresholds(limits: ["uneven-clone-mutation": ["high": 75, "low": 25, "mutants": 1]])

        let strict = try MutationSignalHarness.signal(.unevenCloneMutation, of: snapshot)
        let relaxed = try MutationSignalHarness.signal(.unevenCloneMutation, of: snapshot, thresholds: loose)

        #expect(strict.candidates == 3)
        #expect(strict.items.map { $0.clone?.mass } == [50])
        #expect(strict.items.map(\.score) == [4])
        #expect(strict.items.first?.clone?.mutation?.copies.map { "\($0.killed)/\($0.scored)" } == ["4/5", "1/5"])
        #expect(strict.rule.contains("8 copies of 4 classes = 0 in generated files + 0 in files without full results "
            + "(unresolved or unlisted) + 1 with fewer than 2 scored mutants + 7 measured; 4 = 3 with at least 2 "
            + "measured copies + 1 with fewer; 3 = 1 with a copy at least 80% and one at most 20% killed + 2 without"))
        #expect(relaxed.candidates == 4)
        #expect(relaxed.items.map { $0.clone?.mass } == [40, 30, 50, 20])
        #expect(relaxed.rule.hasPrefix("clone classes with a copy at least 75% and a copy at most 25% of its mutants "
            + "killed (code no test ran counting as unkilled), copies with at least 1 scored mutant (build errors "
            + "aside); scored by the unkilled mutants of the copies at most 25% killed; "))
        #expect(relaxed.rule.contains("+ 0 with fewer than 1 scored mutant + 8 measured; 4 = 4 with at least 2"))
        #expect(MutationSignalHarness.unbalanced(strict.rule).isEmpty)
        #expect(MutationSignalHarness.unbalanced(relaxed.rule).isEmpty)
    }

    @Test("""
        copies in generated files, in files without full results and with too few scored mutants are skipped and \
        counted apart
        """)
    func skippedCopies() throws {
        let generated = "Sources/Lib/Twins.generated.swift"
        let changed = "Sources/Lib/Changed.swift"
        let edited = "Sources/Lib/Edited.swift"
        let other = { (letter: String, file: String, verdict: MutationVerdict) in
            CloneMutationHarness.mutants(3, verdict, function: 0, letter: letter, file: file)
        }
        let setup = CloneMutationHarness.Setup(
            files: [
                Self.file: UnevenHarness.functions(5),
                generated: CloneMutationHarness.functions(1, letter: "h"),
                changed: CloneMutationHarness.functions(1, letter: "g"),
                edited: CloneMutationHarness.functions(1, letter: "k")
            ],
            clones: [
                // 100% here, 0% in the generated file: one measured copy.
                FakeClone(run: "default", mass: 40, spans: [(Self.file, Self.lines(0)), (generated, Self.lines(0))]),
                // 100% and 0% here, and 0% in a file whose results are unresolved.
                FakeClone(run: "default", mass: 30, spans: [
                    (Self.file, Self.lines(1)), (changed, Self.lines(0)), (Self.file, Self.lines(2))
                ]),
                // 100% here, an unlisted file's copy, and a copy with build
                // errors only: one measured copy.
                FakeClone(run: "default", mass: 20, spans: [
                    (Self.file, Self.lines(3)), (edited, Self.lines(0)), (Self.file, Self.lines(4))
                ])
            ],
            mutants: Self.mutants(3, .killed, 0) + other("h", generated, .notCovered)
                + Self.mutants(3, .killed, 1) + other("g", changed, .notCovered) + Self.mutants(3, .survived, 2)
                + Self.mutants(2, .killed, 3) + other("k", edited, .survived) + Self.mutants(3, .buildError, 4),
            dispositions: [changed: .unresolved, edited: .unlisted]
        )

        let snapshot = try CloneMutationHarness.stored(setup)
        let signal = try MutationSignalHarness.signal(.unevenCloneMutation, of: snapshot)

        #expect(snapshot.functions.filter { $0.facts?.generated == true }.map(\.file) == [generated])
        #expect(signal.candidates == 1)
        #expect(signal.items.map { $0.clone?.mass } == [30])
        #expect(signal.items.first?.clone?.copies == 2)
        #expect(signal.items.map(\.subject) == [UnevenHarness.key(2)])
        #expect(signal.rule.contains("; 8 copies of 3 classes = 1 in generated files + 2 in files without full "
            + "results (unresolved or unlisted) + 1 with fewer than 2 scored mutants + 4 measured; 3 = 1 with at "
            + "least 2 measured copies + 2 with fewer; 1 = 1 with a copy at least 80% and one at most 20% killed + 0 "
            + "without; 1 = 1 listed + 0 folded into a listed class; 1 = 1 with a mutant that ran and wasn't "
            + "checked + 0 unkilled only through code no test ran"))
        #expect(MutationSignalHarness.unbalanced(signal.rule).isEmpty)
    }

    /// A nested pair folds into the class holding it; two classes whose
    /// poor copies overlap, neither inside the other, both stay, and the
    /// mutants they share are counted.
    @Test("classes fold on their poor copies; overlapping ones stay and their shared mutants are counted")
    func foldingAndOrder() throws {
        let setup = CloneMutationHarness.Setup(
            files: [Self.file: UnevenHarness.functions(6)],
            clones: [
                Self.clone("default", mass: 60, [Self.lines(0), Self.lines(1)]),
                // Inside the first: its poor copy lies in f1's; a copy in f2
                // of its own keeps it through the merge of the passes.
                Self.clone("default", mass: 40, [2...3, 7...8, 12...13]),
                Self.clone("default", mass: 20, [Self.lines(2), Self.lines(3)]),
                // Its poor copy runs from f3's second line through f4.
                Self.clone("--type3", mass: 15, [17...24, Self.lines(5)])
            ],
            mutants: Self.mutants(3, .killed, 0) + Self.mutants(3, .survived, 1)
                + Self.mutants(2, .killed, 2) + Self.mutants(5, .notCovered, 3)
                + Self.mutants(2, .notCovered, 4) + Self.mutants(2, .killed, 5)
        )

        let snapshot = try CloneMutationHarness.stored(setup)
        let signal = try MutationSignalHarness.signal(.unevenCloneMutation, of: snapshot)

        #expect(signal.candidates == 4)
        // Unchecked first, then by score: 7 before 5.
        #expect(signal.items.map(\.subject) == [UnevenHarness.key(1), UnevenHarness.key(4), UnevenHarness.key(3)])
        #expect(signal.items.map(\.score) == [3, 7, 5])
        let nested = try #require(Self.ordinal(mass: 40, in: snapshot))
        #expect(signal.items.map { $0.clone?.mutation?.folded ?? [-1] } == [[nested], [], []])
        let funnel: String = "9 copies of 4 classes = 0 in generated files + 0 in files without full results "
            + "(unresolved or unlisted) + 0 with fewer than 2 scored mutants + 9 measured; 4 = 4 with at least 2 "
            + "measured copies + 0 with fewer; 4 = 4 with a copy at least 80% and one at most 20% killed + 0 "
            + "without; 4 = 3 listed + 1 folded into a listed class; 3 = 1 with a mutant that ran and wasn't checked "
            + "+ 2 unkilled only through code no test ran (the same evidence as uneven clone testing's coverage part); "
            + "5 mutants counted by more than one item"
        #expect(signal.rule.hasSuffix(funnel))
        #expect(MutationSignalHarness.unbalanced(signal.rule).isEmpty)
    }

    @Test("""
        without the clone detector or a mutation run the signal is left out, naming the collector; results not \
        listing code no test ran add a note
        """)
    func leftOutAndNotes() throws {
        let base = CloneMutationHarness.Setup(
            files: [Self.file: UnevenHarness.functions(2)],
            clones: [Self.clone("default", mass: 40, [Self.lines(0), Self.lines(1)])],
            mutants: Self.mutants(2, .killed, 0) + Self.mutants(2, .survived, 1)
        )
        var withoutClones = base
        withoutClones.withClones = false
        var withoutMutation = base
        withoutMutation.withMutation = false
        var unlisted = base
        unlisted.listsNotCovered = false

        let noClones = try Self.signal(withoutClones)
        let noMutation = try Self.signal(withoutMutation)
        let noted = try Self.signal(unlisted)

        #expect(noClones.leftOut?.hasPrefix("needs swiftclonedetector: skipped") == true)
        #expect(noClones.rule == UnevenCloneMutation.rule(thresholds: SignalThresholds()))
        #expect(noMutation.leftOut == "needs swiftmutator: skipped, not requested; scan --mutation runs it")
        #expect(noMutation.items.isEmpty && noMutation.candidates == 0)
        #expect(noted.leftOut == nil && noted.items.count == 1)
        #expect(noted.rule.hasSuffix("; 0 mutants counted by more than one item; " + WeakTests.notListedNote))
    }
}
