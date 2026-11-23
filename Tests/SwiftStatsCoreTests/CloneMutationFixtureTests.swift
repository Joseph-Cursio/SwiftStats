//
//  CloneMutationFixtureTests.swift
//  SwiftStatsCoreTests
//
//  Uneven clone testing's mutation part on the Mutation fixture end to end
//  (design §7.4, §11): its copy scanned with a fake SwiftCloneDetector
//  reporting the fixture's clone pair, `Core.normalizedA` (tested exactly)
//  and `Extras.normalizedB` (no test runs it), given its recorded
//  SwiftMutator run mapped as a scan maps it, stored and read back. The
//  pair's statement sequences, reported alone (the merge of the passes
//  would drop them beside the whole functions holding them), end in
//  `log.append(scaled.count)`, whose RemoveSideEffects mutant SwiftMutator
//  points one past the statement, outside a copy ending there; its anchor,
//  the statement's last character, keeps it inside.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Uneven clone testing (mutation) on the fixture")
struct CloneMutationFixtureTests {
    /// The tested copy's file.
    private static let first = "Sources/Core/NormalizeA.swift"
    /// The untested copy's file.
    private static let second = "Sources/Extras/NormalizeB.swift"
    /// The column `log.append(scaled.count)` ends before, in both copies.
    private static let appendEnd = 29

    /// The pair of whole functions.
    private static let functions = FakeClone(
        run: "default",
        mass: 60,
        spans: [(first, 6...11), (second, 2...7)]
    )

    /// The pair of statement sequences from `let total` through
    /// `log.append(scaled.count)`.
    private static let statements = FakeClone(
        run: "--sequence",
        mass: 40,
        spans: [(first, 7...9), (second, 3...5)],
        endColumn: appendEnd
    )

    /// The fixture scanned with a fake detector reporting `clones` and its
    /// recorded mutation run, stored and read back.
    private static func stored(_ clones: [FakeClone]) throws -> StoredSnapshot {
        var outputs: [String: String] = [:]
        for run in ["default", "--type3", "--sequence", "--type1"] {
            outputs[run] = try CloneRepository.json(clones.filter { $0.run == run }, run: run)
        }
        let tool = try FakeTool.makeCloneDetector(outputs: outputs, errors: [:], statuses: [:])
        defer { CloneHarness.remove(tool) }
        let mapping = try MappingHarness.mutation()
        defer { mapping.package.remove() }
        let scanned = try SnapshotHarness.scan(
            mapping.package,
            commit: "c1",
            build: SnapshotHarness.build,
            tools: CloneHarness.locator(tool)
        )
        let (results, suspects) = try MappingHarness.fullRun(of: MutationFixture.directory)
        let snapshot = MutationSnapshots.replacing(
            scanned,
            git: scanned.info.git,
            mutation: MutationRows.normalized(mapping.report(results, suspects: suspects)),
            run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
        )
        let directory = try SnapshotHarness.temporaryDirectory("CloneMutationFixture")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        return try store.load(id: try store.save(snapshot))
    }

    @Test("the clone pair is listed by its untested copy, unkilled only through code no test ran")
    func pair() throws {
        let snapshot = try Self.stored([Self.functions])
        let signal = try MutationSignalHarness.signal(.unevenCloneMutation, of: snapshot)

        #expect(signal.leftOut == nil)
        #expect(signal.candidates == 1)
        #expect(signal.items.map(\.subject) == [MutationSignalFixtureTests.normalizedB])
        let item = try #require(signal.items.first)
        #expect(item.file == Self.second && item.line == 2 && item.score == 7)
        #expect(item.clone?.mutation?.folded.isEmpty == true)
        #expect(item.clone?.mutation?.copies.map { [$0.killed, $0.scored, $0.runButUnchecked, $0.unrun] }
            == [[7, 7, 0, 0], [0, 7, 0, 7]])
        let funnel: String = "2 copies of 1 class = 0 in generated files + 0 in files without full results "
            + "(unresolved or unlisted) + 0 with fewer than 2 scored mutants + 2 measured; 1 = 1 with at least 2 "
            + "measured copies + 0 with fewer; 1 = 1 with a copy at least 80% and one at most 20% killed + 0 "
            + "without; 1 = 1 listed + 0 folded into a listed class; 1 = 0 with a mutant that ran and wasn't checked "
            + "+ 1 unkilled only through code no test ran (the same evidence as uneven clone testing's coverage part); "
            + "0 mutants counted by more than one item"
        #expect(signal.rule.hasSuffix(funnel))
        #expect(MutationSignalHarness.unbalanced(signal.rule).isEmpty)
    }

    @Test("""
        a statement-sequence copy ending in a discarded call holds its RemoveSideEffects mutant, pointed past the \
        copy's end and anchored inside it
        """)
    func lastStatement() throws {
        let snapshot = try Self.stored([Self.statements])
        let signal = try MutationSignalHarness.signal(.unevenCloneMutation, of: snapshot)

        let removals = try #require(snapshot.mutation?.report.mutants.filter { $0.operatorID == "RemoveSideEffects" })
        let ranges = snapshot.cloneClasses.first?.instances.map(\.range) ?? []
        #expect(removals.map(\.path) == [Self.first, Self.second])
        #expect(zip(removals, ranges).allSatisfy { mutant, range in
            range.contains(SourcePosition(line: mutant.line, column: mutant.column)) == false
                && mutant.anchor.map(range.contains) == true
        })
        #expect(ranges.count == 2)
        #expect(signal.items.map(\.subject) == [MutationSignalFixtureTests.normalizedB])
        #expect(signal.items.first?.clone?.mutation?.copies.map { [$0.killed, $0.scored, $0.unrun] }
            == [[6, 6, 0], [0, 6, 6]])
        #expect(signal.items.map(\.score) == [6])
    }
}
