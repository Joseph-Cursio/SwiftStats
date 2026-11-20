//
//  DivergentCloneMatchingTests.swift
//  SwiftStatsCoreTests
//
//  Which earlier copies divergent clones (PRD §8) reads, on git fixtures:
//  `#if` twins, keyed apart by their conditions, are read at their own
//  lines; a copy whose family now has no committed history is skipped,
//  never read as unchanged.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Divergent clone matching")
struct DivergentCloneMatchingTests {
    @Test("a fix made in one `#if` twin only lists the pair, the twins keyed apart by their conditions")
    func twinPair() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let file = "Sources/Lib/Render.swift"
        let twin = """
        func render(_ values: [Int]) -> Int {
            var total = 0
            for value in values {
                total += value * 2
            }
            return total
        }
        """
        let twins = "#if os(macOS)\n\(twin)\n#else\n\(twin)\n#endif\n"
        try repository.commit([file: twins], "Add render", day: 0)
        try repository.report([FakeClone(run: "default", mass: 30, spans: [(file, 2...8), (file, 10...16)])])
        try repository.scan()

        let fixed = twins.replacingOccurrences(
            of: "value * 2\n    }\n    return total\n}\n#endif",
            with: "value * 3\n    }\n    return total\n}\n#endif"
        )
        try repository.commit([file: fixed], "Fix the other platforms", day: 1)
        let signal = try repository.signal(.divergentClones, id: try repository.scan())

        #expect(signal.candidates == 1)
        let item = try #require(signal.items.first)
        #expect(signal.items.count == 1)
        #expect("\(item.file):\(item.line)" == "Sources/Lib/Render.swift:2")
        let divergence = try #require(item.clone?.divergence)
        #expect(divergence.changed.map(\.line) == [10])
        #expect(divergence.unchanged.map(\.line) == [2])
    }

    @Test("a copy whose family has no committed history is skipped, not read as unchanged")
    func uncommittedCopy() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let (file, hosts) = (DivergentCloneTests.hostsFile, DivergentCloneTests.hosts)
        let spareFile = "Sources/Lib/Spare.swift"
        try repository.commit([file: hosts], "Add hosts", day: 0)
        try repository.report([DivergentCloneTests.loops(["first", "second"])])
        try repository.scan()
        let edited = hosts.replacingOccurrences(
            of: "total += value * 2\n    }\n    return total + base",
            with: "total += value * 3\n    }\n    return total + base"
        )
        let secondBody = hosts.components(separatedBy: "func second(")[1].components(separatedBy: "func third(")[0]
        try repository.commit([file: edited, spareFile: "func spare(" + secondBody], "Add a spare", day: 1)

        // `second` renamed and the spare deleted in the working tree only:
        // the earlier `second` matches the rename by its body, but the
        // committed body isn't unique, so the rename has no history.
        try repository.repository.write([
            file: edited.replacingOccurrences(of: "func second(", with: "func secondOnly("),
            spareFile: ""
        ])
        let signal = try repository.signal(.divergentClones, id: try repository.scan())

        #expect(signal.items.isEmpty)
        #expect(signal.candidates == 0)
        #expect(signal.rule.contains("; 1 copies with no production family"))
    }
}
