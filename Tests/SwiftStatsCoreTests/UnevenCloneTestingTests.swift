//
//  UnevenCloneTestingTests.swift
//  SwiftStatsCoreTests
//
//  Uneven clone testing, coverage part (PRD §8, M5): which classes are
//  listed, their scores and subjects, the copies skipped, folding on the
//  poorly covered copies (a nested trio, an equal pair), and the lines
//  more than one item counts.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Uneven clone testing")
struct UnevenCloneTestingTests {
    /// The functions file.
    private static let file = UnevenHarness.file
    /// A file the coverage holds no line data for.
    private static let other = "Sources/Lib/Other.swift"

    /// The lines of function `index`.
    private static func lines(_ index: Int) -> ClosedRange<Int> {
        UnevenHarness.lines(of: index)
    }

    /// The ordinal of the class of `mass` in `snapshot`.
    private static func ordinal(mass: Int, in snapshot: StoredSnapshot) -> Int? {
        snapshot.cloneClasses.first { $0.mass == mass }?.ordinal
    }

    @Test("a class with a copy at least 80% and one at most 20% covered is listed by its least covered copy")
    func listing() throws {
        let files = [
            Self.file: UnevenHarness.functions(6),
            Self.other: "func g0(_ value: Int) -> Int {\n    let step = value + 9\n    return step * 2\n}\n"
        ]
        let clones = [
            FakeClone(run: "default", mass: 40, spans: [(Self.file, Self.lines(0)), (Self.file, Self.lines(1))]),
            // 50% and 0%: no copy is well covered.
            FakeClone(run: "default", mass: 30, spans: [(Self.file, Self.lines(2)), (Self.file, Self.lines(1))]),
            // 100%, 25% and 0%.
            FakeClone(run: "--sequence", mass: 20, spans: [
                (Self.file, Self.lines(5)), (Self.file, Self.lines(3)), (Self.file, Self.lines(4))
            ]),
            // A copy in a file with no line data is skipped, leaving one.
            FakeClone(run: "default", mass: 10, spans: [(Self.file, Self.lines(0)), (Self.other, 1...4)])
        ]
        let runs = [
            Self.file: [
                UnevenHarness.run(Self.lines(0), 3),
                UnevenHarness.run(Self.lines(1), 0),
                UnevenHarness.run(11...12, 1),
                UnevenHarness.run(13...14, 0),
                UnevenHarness.run(16...16, 1),
                UnevenHarness.run(17...19, 0),
                UnevenHarness.run(Self.lines(4), 0),
                UnevenHarness.run(Self.lines(5), 2)
            ]
        ]

        let signal = try SignalHarness.signal(
            .unevenCloneTesting,
            of: try UnevenHarness.stored(files, clones: clones, runs: runs)
        )

        #expect(signal.leftOut == nil)
        #expect(signal.candidates == 3)
        #expect(signal.rule == UnevenCloneTesting.rule + "; 1 copies with no mapped line are skipped, leaving 1 "
            + "classes with fewer than 2 measurable copies out; 0 classes whose poorly covered copies lie inside a "
            + "listed class's are folded into it; 0 uncovered lines are counted by more than one item")
        // Equal scores: the larger mass first.
        #expect(signal.items.map(\.subject) == [UnevenHarness.key(1), UnevenHarness.key(4)])
        #expect(signal.items.map(\.score) == [4, 4])
        let sequence = try #require(signal.items.last?.clone)
        #expect(sequence.copies == 3)
        #expect(sequence.lines == 4)
        #expect(sequence.coverage?.folded.isEmpty == true)
        #expect(sequence.coverage?.copies == [
            SignalItem.CoveredCopy(file: Self.file, line: 16, family: UnevenHarness.key(3), covered: 1, mapped: 4),
            SignalItem.CoveredCopy(file: Self.file, line: 21, family: UnevenHarness.key(4), covered: 0, mapped: 4),
            SignalItem.CoveredCopy(file: Self.file, line: 26, family: UnevenHarness.key(5), covered: 4, mapped: 4)
        ])
        let row: String = "| 2 | `func f4(_: Int) -> Int` (Sources/Lib/Twins.swift:21) | 4 | "
            + "`func f3(_: Int) -> Int` (Sources/Lib/Twins.swift:16): 1/4; `func f4(_: Int) -> Int` "
            + "(Sources/Lib/Twins.swift:21): 0/4; `func f5(_: Int) -> Int` (Sources/Lib/Twins.swift:26): 4/4 | "
            + "sequence | — | yes |"
        #expect(SignalHarness.rows(signal).last == row)
    }

    /// A nested trio folds into the outermost class, an equal pair into the
    /// more specific class; partial overlaps stay.
    @Test("classes fold on their poorly covered copies; overlapping ones stay, and their shared lines are counted")
    func folding() throws {
        let files = [Self.file: UnevenHarness.functions(8)]
        let clones = [
            // The trio: each poorly covered copy inside the one before,
            // each class with a copy of its own so the merge keeps it.
            FakeClone(run: "default", mass: 60, spans: [(Self.file, Self.lines(0)), (Self.file, Self.lines(1))]),
            FakeClone(run: "default", mass: 40, spans: [(Self.file, 2...3), (Self.file, 7...8), (Self.file, 12...13)]),
            FakeClone(run: "default", mass: 20, spans: [(Self.file, 2...2), (Self.file, 7...7), (Self.file, 36...36)]),
            // The pair: the same poorly covered copy.
            FakeClone(run: "--sequence", mass: 50, spans: [(Self.file, Self.lines(2)), (Self.file, Self.lines(3))]),
            FakeClone(run: "default", mass: 30, spans: [(Self.file, Self.lines(6)), (Self.file, Self.lines(3))]),
            // Overlapping, neither inside the other.
            FakeClone(run: "--type3", mass: 25, spans: [(Self.file, Self.lines(2)), (Self.file, 21...26)]),
            FakeClone(run: "--type3", mass: 24, spans: [(Self.file, Self.lines(6)), (Self.file, 24...27)]),
            // Two copies at 0%: the one with more uncovered lines names it.
            FakeClone(run: "default", mass: 15, spans: [
                (Self.file, Self.lines(0)), (Self.file, 21...22), (Self.file, Self.lines(5))
            ])
        ]
        let covered: Set<Int> = [0, 2, 6, 7]
        let fileRuns: [CoverageLineRun] = (0..<8).map { index in
            UnevenHarness.run(Self.lines(index), covered.contains(index) ? 1 : 0)
        }
        let runs = [Self.file: fileRuns]

        let snapshot = try UnevenHarness.stored(files, clones: clones, runs: runs)
        let signal = try SignalHarness.signal(.unevenCloneTesting, of: snapshot)
        let ordinal = { (mass: Int) -> Int? in Self.ordinal(mass: mass, in: snapshot) }

        #expect(snapshot.cloneClasses.count == 8)
        #expect(signal.candidates == 8)
        #expect(signal.items.map(\.subject) == [
            UnevenHarness.key(5), UnevenHarness.key(4), UnevenHarness.key(1), UnevenHarness.key(3), "\(Self.file):24"
        ])
        #expect(signal.items.map(\.score) == [6, 5, 4, 4, 3])
        let masses: [Int?] = signal.items.map { $0.clone?.mass }
        #expect(masses == [15, 25, 60, 30, 24])
        let trio: [Int] = try [#require(ordinal(40)), #require(ordinal(20))].sorted()
        let pair: [Int] = [try #require(ordinal(50))]
        let folded: [[Int]] = signal.items.map { $0.clone?.coverage?.folded ?? [-1] }
        #expect(folded == [[], [], trio, pair, []])
        // Lines 21, 22, 24, 26 and 27 are each counted by two or three items.
        #expect(signal.rule.hasSuffix("; 0 copies with no mapped line are skipped, leaving 0 classes with fewer "
            + "than 2 measurable copies out; 3 classes whose poorly covered copies lie inside a listed class's are "
            + "folded into it; 5 uncovered lines are counted by more than one item"))
        // The equal pair keeps the subtree class, though its mass is smaller.
        #expect(signal.items[3].clone?.pass == .subtree)
        // A copy no family holds is named by its file and first line.
        #expect(SignalHarness.rows(signal).last?.hasPrefix("| 5 | `Sources/Lib/Twins.swift:24` "
            + "(Sources/Lib/Twins.swift:24) | 3 | ") == true)
    }

    @Test("without coverage the signal is left out, naming the skipped coverage run")
    func withoutCoverage() throws {
        let files = [Self.file: UnevenHarness.functions(2)]
        let clones = [
            FakeClone(run: "default", mass: 40, spans: [(Self.file, Self.lines(0)), (Self.file, Self.lines(1))])
        ]

        let signal = try SignalHarness.signal(.unevenCloneTesting, of: try UnevenHarness.stored(files, clones: clones))

        #expect(signal.leftOut == "needs coverage: skipped, not requested; scan --coverage runs it")
        #expect(signal.items.isEmpty)
    }
}
