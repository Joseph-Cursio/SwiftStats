//
//  DivergentCloneTests.swift
//  SwiftStatsCoreTests
//
//  Divergent clones (PRD §8) on git fixtures: a commit with clone data is
//  scanned, the code changes, and the signal compares the later scan with
//  it through real history and a real diff.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Divergent clones")
struct DivergentCloneTests {
    /// The file holding the hosts of a cloned loop.
    static let hostsFile = "Sources/Lib/Hosts.swift"
    /// Three functions sharing a loop (lines 3–6, 12–15, 21–24) and
    /// differing around it.
    static let hosts = """
    func first(_ values: [Int]) -> Int {
        let base = values.count
        var total = 0
        for value in values {
            total += value * 2
        }
        return total + base
    }

    func second(_ values: [Int]) -> Int {
        let offset = values.first ?? 0
        var total = 0
        for value in values {
            total += value * 2
        }
        return total - offset
    }

    func third(_ values: [Int]) -> Int {
        let limit = values.last ?? 0
        var total = 0
        for value in values {
            total += value * 2
        }
        return total * limit
    }

    """

    /// The loop's class over the hosts named, by their loops' lines.
    static func loops(_ names: [String]) -> FakeClone {
        let spans = names.map { name in
            let host = CloneRepository.lines(from: "func \(name)(", to: "return total", in: hosts)
            return (path: hostsFile, lines: (host.lowerBound + 2)...(host.upperBound - 1))
        }
        return FakeClone(run: "default", mass: 30, spans: spans)
    }

    @Test("an edit outside the cloned loop lists nothing; an edit inside it lists the class")
    func editInsideOrOutside() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let start = try repository.commit([Self.hostsFile: Self.hosts], "Add hosts", day: 0)
        try repository.report([Self.loops(["first", "second"])])
        try repository.scan()

        let outsideText = Self.hosts.replacingOccurrences(of: "values.count", with: "values.count + 1")
        try repository.commit([Self.hostsFile: outsideText], "Count one more", day: 1)
        let outside = try repository.signal(.divergentClones, id: try repository.scan())
        let insideText = outsideText.replacingOccurrences(
            of: "total += value * 2\n    }\n    return total + base",
            with: "total += value * 3\n    }\n    return total + base"
        )
        try repository.commit([Self.hostsFile: insideText], "Triple the values", day: 2)
        let inside = try repository.signal(.divergentClones, id: try repository.scan())

        #expect(outside.leftOut == nil)
        #expect(outside.candidates == 1)
        #expect(outside.items.isEmpty)
        let item = try #require(inside.items.first)
        #expect(inside.items.count == 1)
        #expect(item.subject == "Lib::func second(_: [Int]) -> Int")
        #expect("\(item.file):\(item.line)" == "Sources/Lib/Hosts.swift:10")
        // Two loops of four stripped lines, over one copy beyond the first.
        #expect(item.score == 8)
        #expect(item.member)
        let divergence = try #require(item.clone?.divergence)
        #expect(divergence.sinceCommit == start)
        #expect(divergence.folded.isEmpty)
        #expect(divergence.changed.map(\.family) == ["Lib::func first(_: [Int]) -> Int"])
        // Both commits since changed `first`; only the second touched its loop.
        #expect(divergence.changed.map(\.changes) == [2])
        #expect(divergence.changed.map(\.lastChange) == ["2026-01-03T00:00:00Z"])
        #expect(divergence.unchanged.map(\.family) == ["Lib::func second(_: [Int]) -> Int"])
        #expect(divergence.unchanged.map(\.lastChange) == [nil])
        #expect(inside.rule.contains(
            "since \(start.prefix(10)) of 2026-01-01, the earliest snapshot with clone data, so the period is "
                + "shorter than the 90-day window; 0 copies"
        ))
        #expect(SignalHarness.rows(inside).last == "| 1 | `func second(_: [Int]) -> Int` (Sources/Lib/Hosts.swift:10) "
            + "| 8 | `func first(_: [Int]) -> Int` (Sources/Lib/Hosts.swift:1): 2 commits, last 2026-01-03 "
            + "| renamed | 2 | 8 | — | yes |")
    }

    @Test("a sweep changing a copy leaves it unchanged")
    func sweepOnly() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let other = "Sources/Lib/Other.swift"
        try repository.commit(
            [
                Self.hostsFile: Self.hosts,
                other: "func other() -> Int {\n    1\n}\n",
                ".swiftstats.yml": "history:\n  bulk_files: 1\n"
            ],
            "Add hosts",
            day: 0
        )
        try repository.report([Self.loops(["first", "second"])])
        try repository.scan()
        let changed = Self.hosts.replacingOccurrences(
            of: "total += value * 2\n    }\n    return total + base",
            with: "total += value * 3\n    }\n    return total + base"
        )

        try repository.commit([Self.hostsFile: changed, other: "func other() -> Int {\n    2\n}\n"], "Reformat", day: 1)
        let signal = try repository.signal(.divergentClones, id: try repository.scan())

        #expect(signal.leftOut == nil)
        #expect(signal.candidates == 1)
        #expect(signal.items.isEmpty)
    }

    @Test("copies with no production family now are skipped, and a class left with one copy isn't in the pool")
    func unmatchedCopies() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let pairsFile = "Sources/Lib/Pairs.swift"
        let pairs = """
        func fourth(_ value: Int) -> Int {
            let doubled = value * 2
            return doubled + 1
        }

        func fifth(_ value: Int) -> Int {
            let doubled = value * 2
            return doubled + 1
        }

        """
        try repository.commit([Self.hostsFile: Self.hosts, pairsFile: pairs], "Add hosts", day: 0)
        let wholes = FakeClone(run: "default", mass: 20, spans: [(pairsFile, 1...4), (pairsFile, 6...9)])
        try repository.report([Self.loops(["first", "second", "third"]), wholes])
        try repository.scan()
        let withoutThird = Self.hosts
            .components(separatedBy: "func third(")[0]
            .replacingOccurrences(
                of: "total += value * 2\n    }\n    return total + base",
                with: "total += value * 3\n    }\n    return total + base"
            )

        try repository.commit(
            [Self.hostsFile: withoutThird, pairsFile: pairs.components(separatedBy: "func fifth(")[0]],
            "Drop third and fifth",
            day: 1
        )
        let signal = try repository.signal(.divergentClones, id: try repository.scan())

        #expect(signal.candidates == 1)
        #expect(signal.items.map(\.subject) == ["Lib::func second(_: [Int]) -> Int"])
        #expect(signal.items.first?.clone?.copies == 2)
        #expect(signal.rule.contains(
            "; 2 copies with no production family outside generated files with known history now are skipped"
        ))
    }

    @Test("a renamed class of whole types pairs its members by position")
    func positionalSlots() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let file = "Sources/Lib/Shapes.swift"
        let shapes = """
        struct Alpha {
            func area(_ side: Int) -> Int {
                let doubled = side * 2
                return doubled * side
            }

            func edge(_ side: Int) -> Int {
                let tripled = side * 3
                return tripled + side
            }
        }

        struct Beta {
            func size(_ length: Int) -> Int {
                let doubled = length * 2
                return doubled * length
            }

            func rim(_ length: Int) -> Int {
                let tripled = length * 3
                return tripled + length
            }
        }

        """
        try repository.commit([file: shapes], "Add shapes", day: 0)
        try repository.report([FakeClone(run: "default", mass: 60, spans: [(file, 1...11), (file, 13...23)])])
        try repository.scan()

        let edited = shapes.replacingOccurrences(of: "side * 3", with: "side * 4")
        try repository.commit([file: edited], "Widen the edge", day: 1)
        let signal = try repository.signal(.divergentClones, id: try repository.scan())

        let item = try #require(signal.items.first)
        #expect(signal.items.count == 1)
        #expect(item.subject == "Lib::Beta::func rim(_: Int) -> Int")
        #expect(item.clone?.divergence?.changed.map(\.family) == ["Lib::Alpha::func edge(_: Int) -> Int"])
        // The edge and the rim, four stripped lines each.
        #expect(item.score == 8)
        #expect(item.clone?.lines == 8)
    }

    @Test("near-miss types pair methods by signature, and a method without a partner takes no slot")
    func signatureSlots() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let file = "Sources/Lib/Units.swift"
        let units = """
        struct Gamma {
            func scale(_ value: Int) -> Int {
                let doubled = value * 2
                return doubled
            }

            func onlyGamma() -> Int {
                let base = 3
                return base
            }
        }

        struct Delta {
            func scale(_ value: Int) -> Int {
                let doubled = value * 2
                return doubled
            }

            func onlyDelta() -> String {
                let name = "delta"
                return name
            }
        }

        """
        try repository.commit([file: units], "Add units", day: 0)
        try repository.report([FakeClone(run: "--type3", mass: 50, spans: [(file, 1...11), (file, 13...23)])])
        try repository.scan()

        let unpaired = units.replacingOccurrences(of: "let base = 3", with: "let base = 4")
        try repository.commit([file: unpaired], "Raise the base", day: 1)
        let afterUnpaired = try repository.signal(.divergentClones, id: try repository.scan())
        let paired = unpaired.replacingOccurrences(
            of: "let doubled = value * 2\n        return doubled\n    }\n\n    func onlyGamma",
            with: "let doubled = value * 5\n        return doubled\n    }\n\n    func onlyGamma"
        )
        try repository.commit([file: paired], "Scale further", day: 2)
        let afterPaired = try repository.signal(.divergentClones, id: try repository.scan())

        #expect(afterUnpaired.candidates == 1)
        #expect(afterUnpaired.items.isEmpty)
        let item = try #require(afterPaired.items.first)
        #expect(afterPaired.items.count == 1)
        #expect(item.subject == "Lib::Delta::func scale(_: Int) -> Int")
        #expect(item.clone?.divergence?.changed.map(\.family) == ["Lib::Gamma::func scale(_: Int) -> Int"])
        // The two `scale(_:)` methods, four stripped lines each.
        #expect(item.score == 8)
        #expect(item.clone?.pass == .nearMiss)
    }
}
