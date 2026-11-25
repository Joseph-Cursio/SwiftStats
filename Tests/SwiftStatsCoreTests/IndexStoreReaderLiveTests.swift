//
//  IndexStoreReaderLiveTests.swift
//  SwiftStatsCoreTests
//
//  `IndexStoreReader` over a real index store, against the checker's own
//  ctypes reader (M7, design §13 step 4b, check u0): every non-system unit
//  and every record `Scripts/index-check.py dump` wrote, fact for fact.
//  Skipped unless `SWIFTSTATS_LIVE_INDEX` names a dump; the dump names its
//  store and the libIndexStore.dylib it was read with (`store`,
//  `library.path`), which this test reads again, so a plain `swift test`
//  loads no library. Make the dump and the run with:
//
//      python3 -I -B Scripts/index-check.py dump <store> <libIndexStore> \
//          <describe.json> <root> --output <dump.json>
//      SWIFTSTATS_LIVE_INDEX=<dump.json> swift test --filter IndexStoreReaderLiveTests
//
//  The dump sorts what the reader gives in its own order (relations and
//  occurrences, module dependencies), so both sides are put in one order
//  before they are compared; unit names and record names are compared as
//  the reader gives them.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The reader against the checker's dump of the same store.
@Suite(
    "Index store reader, live",
    .enabled(if: ProcessInfo.processInfo.environment[IndexFixture.liveVariable] != nil)
)
struct IndexStoreReaderLiveTests {
    /// The library a dump was read with.
    private struct DumpLibrary: Decodable, Sendable {
        /// Its real path.
        let path: String
    }

    /// The parts of a dump this test reads.
    private struct Dump: Decodable, Sendable {
        /// The store's real path.
        let store: String
        /// The library the dump was read with.
        let library: DumpLibrary
        /// Every non-system unit.
        let units: [IndexUnitFact]
        /// The records of the units under the dump's root.
        let records: [IndexRecordFact]
    }

    /// What the comparison found.
    private struct Comparison: Sendable {
        /// The units the reader names, system units included.
        var unitNames = 0
        /// Its system units.
        var systemUnits = 0
        /// The records compared.
        var records = 0
        /// The occurrences compared.
        var occurrences = 0
        /// How long the reader took, in seconds.
        var seconds = 0.0
        /// Each difference, as text.
        var differences: [String] = []
    }

    /// How long the reader may take, in seconds.
    private static let timeout: TimeInterval = 600
    /// The differences printed, at most.
    private static let shown = 20

    /// Whether `lhs` comes before `rhs` in code point order.
    private static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars)
    }

    /// Whether relation `lhs` comes before `rhs`: by USR, roles, kind,
    /// subkind, properties, then name, as the dump orders them.
    private static func precedes(_ lhs: IndexOccurrenceFact.Relation, _ rhs: IndexOccurrenceFact.Relation) -> Bool {
        if lhs.usr != rhs.usr {
            return precedes(lhs.usr, rhs.usr)
        }
        let left = (lhs.roles, lhs.kind, lhs.subkind, lhs.properties)
        let right = (rhs.roles, rhs.kind, rhs.subkind, rhs.properties)
        if left != right {
            return left < right
        }
        return precedes(lhs.name, rhs.name)
    }

    /// `occurrence` with its relations in the dump's order.
    private static func ordered(_ occurrence: IndexOccurrenceFact) -> IndexOccurrenceFact {
        IndexOccurrenceFact(
            line: occurrence.line,
            column: occurrence.column,
            roles: occurrence.roles,
            usr: occurrence.usr,
            name: occurrence.name,
            kind: occurrence.kind,
            subkind: occurrence.subkind,
            properties: occurrence.properties,
            relations: occurrence.relations.sorted(by: precedes)
        )
    }

    /// `record`'s occurrences, relations ordered, counted as a multiset.
    private static func occurrenceCounts(_ record: IndexRecordFact) -> [IndexOccurrenceFact: Int] {
        record.occurrences.reduce(into: [:]) { counts, occurrence in
            counts[ordered(occurrence), default: 0] += 1
        }
    }

    /// `unit` with its module dependencies by module, then system last.
    private static func ordered(_ unit: IndexUnitFact) -> IndexUnitFact {
        IndexUnitFact(
            name: unit.name,
            module: unit.module,
            mainFile: unit.mainFile,
            target: unit.target,
            isSystem: unit.isSystem,
            modified: unit.modified,
            records: unit.records,
            moduleDependencies: unit.moduleDependencies.sorted { lhs, rhs in
                guard lhs.module == rhs.module else {
                    return precedes(lhs.module, rhs.module)
                }
                return lhs.isSystem == false && rhs.isSystem
            }
        )
    }

    /// The reader's units and records compared with `dump`'s.
    private static func compare(_ dump: Dump) throws -> Comparison {
        var comparison = Comparison()
        let started = Date()
        let reader = try IndexStoreReader.open(
            store: URL(fileURLWithPath: dump.store),
            library: URL(fileURLWithPath: dump.library.path)
        )
        let names = try reader.unitNames()
        let units = try names.map { try reader.unit(named: $0) }
        let records = try dump.records.map { try reader.record(named: $0.name) }
        comparison.seconds = Date().timeIntervalSince(started)
        comparison.unitNames = names.count
        comparison.systemUnits = units.count(where: \.isSystem)
        if names != names.sorted(by: precedes) {
            comparison.differences.append("the unit names aren't in code point order")
        }
        let read = Dictionary(units.filter { $0.isSystem == false }.map { ($0.name, $0) }) { first, _ in first }
        let dumped = Set(dump.units.map(\.name))
        for name in Set(read.keys).symmetricDifference(dumped).sorted() {
            comparison.differences.append("unit \(name) is \(dumped.contains(name) ? "only dumped" : "only read")")
        }
        for unit in dump.units {
            if let mine = read[unit.name], ordered(mine) != ordered(unit) {
                comparison.differences.append("unit \(unit.name): read \(ordered(mine)), dumped \(ordered(unit))")
            }
        }
        for (mine, theirs) in zip(records, dump.records) {
            comparison.records += 1
            comparison.occurrences += theirs.occurrences.count
            if mine.name != theirs.name || mine.file != theirs.file {
                comparison.differences.append(
                    "record \(theirs.name): read \(mine.name) at \(mine.file), dumped at \(theirs.file)"
                )
            }
            if occurrenceCounts(mine) != occurrenceCounts(theirs) {
                comparison.differences.append(
                    "record \(theirs.name): \(mine.occurrences.count) occurrences read, "
                        + "\(theirs.occurrences.count) dumped, or not the same ones"
                )
            }
        }
        return comparison
    }

    @Test("the reader gives every unit and record of the dump, fact for fact")
    func agrees() async throws {
        let path = try #require(ProcessInfo.processInfo.environment[IndexFixture.liveVariable])
        let dump = try JSONDecoder().decode(Dump.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        // The library load goes through `BlockingAsync`, so the reader runs
        // on a thread of its own.
        let run = ThreadRun { Result { try Self.compare(dump) } }
        let deadline = Date().addingTimeInterval(Self.timeout)
        while run.isFinished == false, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(run.isFinished, "the reader didn't finish within \(Self.timeout) s")
        let comparison = try await run.value.get()

        print("""
            live index: \(comparison.unitNames) units read (\(comparison.systemUnits) system), \
            \(dump.units.count) dumped; \(comparison.records) records, \(comparison.occurrences) occurrences; \
            read in \(String(format: "%.2f", comparison.seconds)) s; \(comparison.differences.count) differences
            """)
        for difference in comparison.differences.prefix(Self.shown) {
            print("live index difference: \(difference)")
        }
        #expect(comparison.differences.isEmpty)
        #expect(comparison.records == dump.records.count)
        #expect(comparison.unitNames - comparison.systemUnits == dump.units.count)
    }
}
