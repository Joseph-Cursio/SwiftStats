//
//  UnevenCloneMutationTests+Anchors.swift
//  SwiftStatsCoreTests
//
//  Uneven clone testing, mutation part (design §7.4): which mutants a
//  copy holds, by anchor, start and end line and column, whatever their
//  owner, unmapped ones left out.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Which mutants a copy of a clone class holds.
extension UnevenCloneMutationTests {
    /// The copies start inside their first line, at the function's name
    /// in column 6, and end inside their last line, `return step * 2`,
    /// whose last character is column 19: SwiftMutator points a
    /// RemoveSideEffects mutant one past it, at column 20, outside the
    /// copy, and its anchor, the statement's last character, inside. A
    /// mutant anchored on a copy's first line before its start column, or
    /// on its last line past its end column, is outside it, so containment
    /// compares columns as well as lines.
    @Test("""
        a copy holds the mapped mutants anchored in its range, whatever their owner: one pointed past its last \
        statement counts; one on its first line before its start column, on its last line past its end column, \
        past its last line or unmapped doesn't
        """)
    func anchors() throws {
        let removal = "RemoveSideEffects"
        let mutant = { (verdict: MutationVerdict, line: Int, column: Int, place: MutationPlace, anchor: Int?) in
            var planted = MutationSignalHarness.Planted(verdict: verdict)
            if column == 20 {
                planted.operatorID = removal
            }
            return MutationSignalHarness.mutant(
                planted,
                path: UnevenHarness.file,
                at: SourcePosition(line: line, column: column),
                placement: MutationSignalHarness.Placement(
                    place: place,
                    owner: place == .file ? UnevenHarness.file : UnevenHarness.key((line - 1) / 5),
                    anchor: anchor.map { SourcePosition(line: line, column: $0) }
                )
            )
        }
        let setup = CloneMutationHarness.Setup(
            files: [UnevenHarness.file: UnevenHarness.functions(2)],
            clones: [
                FakeClone(
                    run: "--sequence",
                    mass: 20,
                    spans: [(UnevenHarness.file, 1...3), (UnevenHarness.file, 6...8)],
                    startColumn: 6,
                    endColumn: 20
                )
            ],
            mutants: [
                mutant(.killed, 3, 20, .record, 19),
                mutant(.killed, 2, 16, .file, 16),
                mutant(.survived, 4, 1, .record, 1),
                mutant(.survived, 1, 5, .record, 5),
                mutant(.survived, 2, 18, .unmapped, nil),
                mutant(.survived, 8, 20, .record, 19),
                mutant(.notCovered, 7, 16, .record, 16),
                mutant(.survived, 9, 1, .record, 1),
                mutant(.killed, 8, 21, .record, 20)
            ]
        )

        let snapshot = try CloneMutationHarness.stored(setup)
        let signal = try MutationSignalHarness.signal(.unevenCloneMutation, of: snapshot)

        let ranges = snapshot.cloneClasses.first?.instances.map(\.range) ?? []
        #expect(ranges.map(\.start) == [SourcePosition(line: 1, column: 6), SourcePosition(line: 6, column: 6)])
        #expect(ranges.map(\.end) == [SourcePosition(line: 3, column: 19), SourcePosition(line: 8, column: 19)])
        #expect(ranges.first?.contains(SourcePosition(line: 3, column: 20)) == false)
        #expect(signal.items.map(\.subject) == [UnevenHarness.key(1)])
        #expect(signal.items.first?.clone?.mutation?.copies.map { [$0.killed, $0.scored, $0.runButUnchecked, $0.unrun] }
            == [[2, 2, 0, 0], [0, 2, 1, 1]])
        #expect(signal.items.map(\.score) == [2])
    }
}
