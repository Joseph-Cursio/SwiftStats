import Foundation
@testable import SwiftStatsCore
import Testing

/// The store's v6 columns (M7, design §9.1), on hand-made T1 results
/// covering every nullable column: each block reads back exactly, null
/// where nothing was collected and never zero, lists as JSON arrays and
/// names as written; history's coupling pairs are rows in the history
/// block's order; and columns that don't read are a damaged store, never
/// no results.
@Suite("Store v6 columns")
struct StoreIndexColumnTests {
    @Test("""
        hand-made index results read back exactly: function columns null where nothing was collected, test \
        referrers holding a line break as a JSON array, the units, files and listings in order
        """)
    func indexColumns() throws {
        let made = try TemporaryStore("StoreIndexColumns")
        defer { made.remove() }
        let snapshot = try IndexStoreSamples.snapshot(commit: "c1")

        let stored = try made.store.load(id: try made.store.save(snapshot))

        #expect(stored.index?.report == snapshot.report.index)
        let records = stored.index?.report.records ?? []
        #expect(records.first?.coupling?.references.testReferrers == [IndexStoreSamples.oddReferrer, "testOne()"])
        let functions = """
            SELECT key, ifnull(usr, '-'), ifnull(usrAccessor, '-'), ifnull(usrReason, '-'), ifnull(witness, '-'),
                ifnull(referrersSameModule, '-'), ifnull(referrersTests, '-'), ifnull(testReferrers, '-'),
                ifnull(typeCheckMilliseconds, '-'), ifnull(slowestExpressionMilliseconds, '-')
            FROM function ORDER BY rowid
            """
        let referrers = RowJSON.text([IndexStoreSamples.oddReferrer, "testOne()"])
        #expect(try made.query(functions) == """
            Lib::func one() -> Int|s:3Lib3oneSiyF|s:3Lib3oneSiyFig|-|0|1|2|\(referrers)|12|3
            Lib::func two()|s:3Lib3twoyyF|-|-|1|0|0|[]|-|1
            LibTests::func testOne()|-|-|inactiveIfBranch|-|-|-|-|-|-

            """)
        let scan = """
            SELECT layout, libraryModules, unitsKept, unitsVariant, unitsSystem, unitsOtherPackage, unitsOtherModule,
                unitsStale, unitsDuplicate, unitsQuarantined, records, occurrences, definitionsJoined,
                definitionsImplicit, secondaryUSRs, objcUSRs
            FROM indexScan
            """
        #expect(try made.query(scan) == "swiftbuild|[\"Lib\"]|2|1|9|8|0|1|2|1|4|77|5|3|1|0\n")
        #expect(try made.query("SELECT name, class FROM indexUnit ORDER BY name") == """
            Lib.o-A|variant
            Lib.o-B|kept
            Old.o-C|stale

            """)
        #expect(try made.query("SELECT path, ifnull(sha256, '-') FROM indexFile ORDER BY path") == """
            Sources/Lib/Lib.swift|abc
            Tests/LibTests/LibTests.swift|-

            """)
        let listings = """
            SELECT ordinal, kind, ifnull(subreason, '-'), ifnull(key, '-'), ifnull(symbolKind, '-'), line, column
            FROM usrDisagreement ORDER BY ordinal
            """
        #expect(try made.query(listings) == """
            0|severalUSRs|-|Lib::func one() -> Int|-|1|13
            1|sharedUSR|-|Lib::func two()|-|5|6
            2|noRecord|requirement|-|16|7|10
            3|collision|-|Lib::func two()|-|5|1

            """)
    }

    @Test("""
        hand-made coupling reads back exactly: a dependency edge's references null, local types of one name \
        kept apart by USR, a type's file '' unless file-scoped, and history's coupling pairs as rows in order
        """)
    func couplingColumns() throws {
        let made = try TemporaryStore("StoreIndexColumns")
        defer { made.remove() }
        let snapshot = try IndexStoreSamples.snapshot(commit: "c1")

        let stored = try made.store.load(id: try made.store.save(snapshot))

        #expect(stored.couplingPairs == snapshot.report.history?.coupling)
        #expect(stored.index?.report.types.map(\.usr) == ["s:3Lib6FinderL0_V", "s:3Lib6FinderL_V", "s:3Lib6Hidden"])
        let edges = "SELECT fromModule, toModule, kind, ifnull(\"references\", '-'), files FROM moduleEdge"
        #expect(try made.query(edges + " ORDER BY fromModule") == """
            Lib|RealModule|dependency|-|1
            LibTests|Lib|package|3|1

            """)
        let types = "SELECT typePath, typeFile, usr, referrersTests, ifnull(cycle, '-') FROM typeIndex ORDER BY usr"
        #expect(try made.query(types) == """
            Finder||s:3Lib6FinderL0_V|2|-
            Finder||s:3Lib6FinderL_V|0|-
            Hidden|Sources/Lib/Lib.swift|s:3Lib6Hidden|0|1

            """)
        #expect(try made.query("SELECT via FROM familyReference ORDER BY via") == "direct\nrequirement\n")
        #expect(try made.query("SELECT typePath, typeFile FROM familyTypeReference ORDER BY typePath") == """
            Finder|
            Hidden|Sources/Lib/Lib.swift

            """)
        let pairs = "SELECT ordinal, familyA, familyB, support, changesA, changesB FROM couplingPair ORDER BY ordinal"
        #expect(try made.query(pairs) == """
            0|Lib::func one() -> Int|Lib::func two()|4|5|6
            1|Lib::func two()|LibTests::func testOne()|3|6|3

            """)
    }

    @Test("""
        hand-made build results read back exactly: every count its own column, and an attachment's missing \
        figure null
        """)
    func buildColumns() throws {
        let made = try TemporaryStore("StoreIndexColumns")
        defer { made.remove() }
        let snapshot = try IndexStoreSamples.snapshot(commit: "c1")

        let stored = try made.store.load(id: try made.store.save(snapshot))

        #expect(stored.build?.report == snapshot.report.build)
        let build = """
            SELECT complete, functionEntries, expressionEntries, totalMilliseconds, synthesizedEntries,
                synthesizedMilliseconds, macroEntries, macroMilliseconds, buildEntries, buildMilliseconds,
                outsideRootEntries, outsideRootMilliseconds, fileChangedEntries, fileChangedMilliseconds,
                unscannedEntries, unscannedMilliseconds, changedFiles, unparsedTimingLines, escapedLines,
                otherWarningLines, warningsDropped, warningsUnmapped, pluginWarnings
            FROM buildScan
            """
        #expect(try made.query(build) == "0|18|19|20|5|6|7|8|9|10|11|13|14|15|16|17|21|22|23|24|25|26|27\n")
        let attachments = """
            SELECT owner, attachedTo, ifnull(milliseconds, '-'), ifnull(slowestExpressionMilliseconds, '-')
            FROM timingAttachment ORDER BY attachedTo
            """
        #expect(try made.query(attachments) == "Sources/Lib/Lib.swift|file|4|-\nLib::Hidden|type|-|2\n")
    }

    @Test("""
        hand-made dead-code results read back exactly: every entry of both runs with lists as JSON arrays and \
        classes and places by name, each covered record, and each run's dead lines
        """)
    func deadCodeColumns() throws {
        let made = try TemporaryStore("StoreIndexColumns")
        defer { made.remove() }
        let snapshot = try IndexStoreSamples.snapshot(commit: "c1")

        let stored = try made.store.load(id: try made.store.save(snapshot))

        #expect(stored.deadCode?.report == snapshot.report.deadCode)
        #expect(try made.query("SELECT version, rootsResults, productionResults FROM deadScan") == "3.28.0|3|2\n")
        let declarations = """
            SELECT run, ordinal, hint, ifnull(hintText, '-'), attributes, modifiers, ids, modules, class,
                ifnull(file, '-'), place, ifnull(owner, '-'), ifnull(module, '-'), ifnull(strippedLines, '-')
            FROM deadDeclaration ORDER BY run DESC, ordinal
            """
        #expect(try made.query(declarations) == """
            roots|1|unused|-|[]|[]|["s:3Lib3twoyyF"]|["Lib"]|production|Sources/Lib/Lib.swift|function|\
            Lib::func two()|Lib|1
            roots|2|redundantConformance|replace with: "P"|["@Test"]|["final","private"]|["s:a","s:b"]|\
            ["LibTests"]|test|Tests/LibTests/LibTests.swift|function|LibTests::func testOne()|LibTests|-
            roots|3|unused|-|[]|[]|[]|["Dep"]|outsideRoot|-|unscanned|-|-|-
            production|1|unused|-|[]|[]|["s:3Lib3twoyyF"]|["Lib"]|production|Sources/Lib/Lib.swift|function|\
            Lib::func two()|Lib|1
            production|2|unused|-|[]|[]|["s:3Lib3oneSiyF6secondL_Sivp"]|["Lib"]|local|Sources/Lib/Lib.swift|\
            function|Lib::func one() -> Int|Lib|-

            """)
        #expect(try made.query("SELECT run, key, declaration, via FROM deadRecord ORDER BY run DESC") == """
            roots|Lib::func two()|1|usr
            production|Lib::func two()|1|usr

            """)
        #expect(try made.query("SELECT run, module, lines FROM deadLines ORDER BY run DESC, module") == """
            roots|Lib|1
            roots|Other|0
            production|Lib|1

            """)
    }

    @Test("""
        T1 rows whose class, kind, reason, rule, place, run or JSON columns don't read, or whose referrers \
        are missing beside a witness flag, are a damaged store, never no results
        """)
    func damagedRows() throws {
        let made = try TemporaryStore("StoreIndexColumns")
        defer { made.remove() }
        let snapshot = try IndexStoreSamples.snapshot(commit: "c1")
        let damages: [(statement: String, rows: String)] = [
            ("UPDATE function SET usrReason = 'gone' WHERE usrReason IS NOT NULL", "index"),
            ("UPDATE function SET testReferrers = 'testOne()' WHERE testReferrers IS NOT NULL", "index"),
            ("UPDATE function SET referrersTests = NULL WHERE witness IS NOT NULL", "index"),
            ("UPDATE indexUnit SET class = 'gone'", "index"),
            ("UPDATE indexScan SET libraryModules = 'Lib'", "index"),
            ("UPDATE usrDisagreement SET kind = 'gone' WHERE ordinal = 0", "index"),
            ("UPDATE usrDisagreement SET subreason = 'gone' WHERE subreason IS NOT NULL", "index"),
            ("UPDATE moduleEdge SET kind = 'gone'", "index"),
            ("UPDATE familyReference SET via = 'gone' WHERE via = 'direct'", "index"),
            ("UPDATE timingAttachment SET attachedTo = 'gone'", "build"),
            ("UPDATE deadDeclaration SET class = 'gone' WHERE ordinal = 1", "dead-code"),
            ("UPDATE deadDeclaration SET place = 'gone' WHERE ordinal = 1", "dead-code"),
            ("UPDATE deadDeclaration SET attributes = '{' WHERE ordinal = 1", "dead-code"),
            ("UPDATE deadDeclaration SET run = 'gone' WHERE ordinal = 3", "dead-code"),
            ("UPDATE deadRecord SET via = 'gone'", "dead-code"),
            ("UPDATE deadLines SET run = 'gone' WHERE module = 'Other'", "dead-code")
        ]

        for damage in damages {
            let id = try made.store.save(snapshot)
            try SnapshotHarness.sqlite(made.url, damage.statement)

            #expect(
                throws: StoreError.corruptReport("the \(damage.rows) rows of snapshot \(id)"),
                "\(damage.statement)"
            ) {
                try made.store.load(id: id)
            }
        }
    }
}
