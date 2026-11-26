//
//  TimingFigureTests+Saturation.swift
//  SwiftStatsCoreTests
//
//  The timing mapper's figures at the top of an `Int`: a record's
//  sum, the entries left out and the totals stop at `Int.max` hundredths
//  instead of trapping, and rounding to whole milliseconds stays half up
//  there without overflowing. The build reader's twelve-digit bound keeps
//  real entries far below this, so these entries are written by hand.
//

@testable import SwiftStatsCore
import Testing

/// The timing mapper's figures at the top of an `Int`: sums stop at
/// `Int.max` hundredths, and rounding never overflows.
extension TimingFigureTests {
    @Test(
        "rounding to whole milliseconds stays half up at the top of an Int and never overflows",
        arguments: [
            (Int.max, maximalMilliseconds),
            (Int.max - 8, maximalMilliseconds),
            (Int.max - 57, maximalMilliseconds),
            (Int.max - 58, maximalMilliseconds - 1)
        ]
    )
    func roundingAtTheTop(hundredths: Int, milliseconds: Int) {
        // `Int.max` ends in .07, `Int.max - 8` in .99, `- 57` in .50 and `- 58` in .49.
        #expect(TimingMapper.milliseconds(hundredths) == milliseconds)
    }

    @Test("a function's entries past what an Int holds sum to Int.max hundredths, rounded without trapping")
    func saturatingRecordSum() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let root = library.root
        let mapped = library.mapper.map([
            Self.entry(.function, Int.max, line: 1, column: 13, root: root),
            Self.entry(.function, Self.halfMaximal, line: 1, column: 13, root: root),
            Self.entry(.function, Self.halfMaximal, line: 1, column: 13, root: root)
        ])
        #expect(mapped.records.map(\.key) == ["Lib::func first() -> Int"])
        #expect(mapped.records.map(\.milliseconds) == [Self.maximalMilliseconds])
        #expect(mapped.totals.milliseconds == Self.maximalMilliseconds)
    }

    @Test("entries left out past what an Int holds count their time as Int.max hundredths")
    func saturatingLeftOutSum() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let mapped = library.mapper.map([
            TimingEntry(kind: .function, hundredths: Self.halfMaximal, place: nil, declaration: "f"),
            TimingEntry(kind: .function, hundredths: Self.halfMaximal, place: nil, declaration: "g")
        ])
        #expect(mapped.unmapped.synthesized == BuildEntryCount(entries: 2, milliseconds: Self.maximalMilliseconds))
        #expect(mapped.totals.milliseconds == 0)
    }

    @Test("records whose times add past what an Int holds total Int.max hundredths, each keeping its own")
    func saturatingTotals() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let root = library.root
        let mapped = library.mapper.map([
            Self.entry(.function, Self.halfMaximal, line: 1, column: 13, root: root),
            Self.entry(.function, Self.halfMaximal, line: 2, column: 13, root: root)
        ])
        // 46116860184273879.04 ms each.
        #expect(mapped.records.map(\.milliseconds) == [46_116_860_184_273_879, 46_116_860_184_273_879])
        #expect(mapped.totals.milliseconds == Self.maximalMilliseconds)
    }
}
