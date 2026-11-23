//
//  UnevenCloneMutationTests+Copies.swift
//  SwiftStatsCoreTests
//
//  Uneven clone testing, mutation part (design §7.4): a class's poorly
//  tested copies that overlap count each unkilled mutant once, and the
//  least killed copy that names the item breaks a tie on share by the
//  most unkilled mutants before its file and line.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// How a class's poorly tested copies come to its score and subject.
extension UnevenCloneMutationTests {
    /// Copies over f1 and f2 (lines 6 to 12) and over f2 alone (lines 11
    /// to 14) are both poorly tested and share f2's two mutants.
    @Test("""
        a class's overlapping poorly tested copies count each unkilled mutant once, in its score and in the mutants \
        counted by more than one item
        """)
    func overlappingPoorCopies() throws {
        let file = UnevenHarness.file
        let setup = CloneMutationHarness.Setup(
            files: [file: UnevenHarness.functions(3)],
            clones: [
                FakeClone(run: "default", mass: 40, spans: [
                    (file, UnevenHarness.lines(of: 0)), (file, 6...12), (file, 11...14)
                ])
            ],
            mutants: CloneMutationHarness.mutants(3, .killed, function: 0)
                + CloneMutationHarness.mutants(2, .survived, function: 1)
                + CloneMutationHarness.mutants(2, .notCovered, function: 2)
        )

        let signal = try MutationSignalHarness.signal(
            .unevenCloneMutation,
            of: try CloneMutationHarness.stored(setup)
        )

        #expect(signal.items.first?.clone?.mutation?.copies.map { "\($0.killed)/\($0.scored)" }
            == ["3/3", "0/4", "0/2"])
        #expect(signal.items.map(\.score) == [4])
        #expect(signal.rule.contains("; 0 mutants counted by more than one item"))
    }

    /// Copies over f1 and f2 are both 0% killed; f1's comes first by file
    /// and line, but f2's holds more unkilled mutants, so it names the item.
    @Test("of poorly tested copies tied on share, the one with the most unkilled mutants names the item")
    func leastKilledTie() throws {
        let file = UnevenHarness.file
        let setup = CloneMutationHarness.Setup(
            files: [file: UnevenHarness.functions(3)],
            clones: [
                FakeClone(run: "default", mass: 40, spans: [
                    (file, UnevenHarness.lines(of: 0)), (file, UnevenHarness.lines(of: 1)),
                    (file, UnevenHarness.lines(of: 2))
                ])
            ],
            mutants: CloneMutationHarness.mutants(3, .killed, function: 0)
                + CloneMutationHarness.mutants(2, .survived, function: 1)
                + CloneMutationHarness.mutants(5, .survived, function: 2)
        )

        let signal = try MutationSignalHarness.signal(
            .unevenCloneMutation,
            of: try CloneMutationHarness.stored(setup)
        )

        #expect(signal.items.first?.clone?.mutation?.copies.map { "\($0.killed)/\($0.scored)" }
            == ["3/3", "0/2", "0/5"])
        #expect(signal.items.map(\.subject) == [UnevenHarness.key(2)])
        #expect(signal.items.map(\.line) == [UnevenHarness.lines(of: 2).lowerBound])
        #expect(signal.items.map(\.score) == [7])
    }
}
