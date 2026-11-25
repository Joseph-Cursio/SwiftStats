//
//  IndexStoreSamples.swift
//  SwiftStatsCoreTests
//
//  Hand-made T1 results covering every nullable column of the store's v6
//  tables (M7, design §9.1), written as the scan JSON writes them, and
//  attached to a small library's snapshot as a scan attaches them, with
//  its `build`, `index` and `periphery` runs, so the rows can be checked
//  without a build, an index store or outskirts, the runs recording this
//  build's rules. Also a snapshot with the T1 group not run, as a plain
//  rescan of the same tree makes it, and a history with change-coupling
//  pairs.
//

import Foundation
@testable import SwiftStatsCore

/// T1 results for the store's v6 tables.
enum IndexStoreSamples {
    /// A small library: a public function a test calls, and a function
    /// nothing calls.
    static let files = [
        "Sources/Lib/Lib.swift": "public func one() -> Int {\n    1\n}\n\nfunc two() {}\n",
        "Tests/LibTests/LibTests.swift": "func testOne() {\n    _ = one()\n}\n"
    ]
    /// A test referrer's name holding a line break, a comma and quotes.
    static let oddReferrer = "checks \"one\",\nand more()"

    /// The index block, but for its records: units of three classes, a
    /// file with no hash, every listing kind, a dependency edge with no
    /// references, two local types sharing their target, path and file,
    /// a file-scoped type in a cycle, and family references of both kinds.
    private static let indexJSON = """
        {"store": {"layout": "swiftbuild",
                   "counts": {"system": 9, "otherPackage": 8, "otherModule": 0, "stale": 1, "duplicate": 2,
                              "variant": 1, "kept": 2, "quarantined": 1},
                   "records": 4, "occurrences": 77,
                   "units": [
                     {"name": "Lib.o-A", "target": "Lib", "mainFile": "Sources/Lib/Lib.swift",
                      "triple": "arm64-apple-macosx27.0", "class": "variant"},
                     {"name": "Lib.o-B", "target": "Lib", "mainFile": "Sources/Lib/Lib.swift",
                      "triple": "arm64-apple-macosx27.2", "class": "kept"},
                     {"name": "Old.o-C", "target": "Lib", "mainFile": "Sources/Lib/Old.swift",
                      "triple": "arm64-apple-macosx27.2", "class": "stale"}]},
         "libraryModules": ["Lib"],
         "records": [],
         "definitions": {"joined": 5, "implicit": 3, "secondary": 1, "objc": 0},
         "disagreements": [
           {"kind": "severalUSRs", "usr": "s:3Lib1aF", "key": "Lib::func one() -> Int",
            "file": "Sources/Lib/Lib.swift", "line": 1, "column": 13},
           {"kind": "sharedUSR", "usr": "s:3Lib1bF", "key": "Lib::func two()",
            "file": "Sources/Lib/Lib.swift", "line": 5, "column": 6}],
         "withoutRecord": [
           {"kind": "noRecord", "subreason": "requirement", "usr": "s:3Lib1PP1fyyF", "symbolKind": 16,
            "name": "f()", "file": "Sources/Lib/Lib.swift", "line": 7, "column": 10}],
         "collisions": [
           {"kind": "collision", "usr": "s:3Lib1cF", "key": "Lib::func two()",
            "file": "Sources/Lib/Lib.swift", "line": 5, "column": 1}],
         "moduleEdges": [
           {"fromModule": "Lib", "toModule": "RealModule", "kind": "dependency", "files": 1},
           {"fromModule": "LibTests", "toModule": "Lib", "kind": "package", "references": 3, "files": 1}],
         "types": [
           {"module": "Lib", "typePath": "Finder", "usr": "s:3Lib6FinderL0_V", "referrersSameModule": 0,
            "referrersOtherModules": 0, "referrersTests": 2},
           {"module": "Lib", "typePath": "Finder", "usr": "s:3Lib6FinderL_V", "referrersSameModule": 1,
            "referrersOtherModules": 0, "referrersTests": 0},
           {"module": "Lib", "typePath": "Hidden", "typeFile": "Sources/Lib/Lib.swift", "usr": "s:3Lib6Hidden",
            "referrersSameModule": 2, "referrersOtherModules": 1, "referrersTests": 0, "cycle": 1}],
         "familyReferences": [
           {"fromFamily": "Lib::func one() -> Int", "toFamily": "Lib::func two()", "via": "direct"},
           {"fromFamily": "Lib::func one() -> Int", "toFamily": "Lib::func two()", "via": "requirement"}],
         "familyTypeReferences": [
           {"family": "Lib::func one() -> Int", "module": "Lib", "typePath": "Finder"},
           {"family": "Lib::func one() -> Int", "module": "Lib", "typePath": "Hidden",
            "typeFile": "Sources/Lib/Lib.swift"}],
         "files": [
           {"path": "Sources/Lib/Lib.swift", "sha256": "abc"},
           {"path": "Tests/LibTests/LibTests.swift"}]}
        """

    /// The build block: a record with both figures, one with only an
    /// expression, a type with only expressions and a file with only a
    /// body, and a distinct count in every field.
    private static let buildJSON = """
        {"complete": false,
         "records": [
           {"key": "Lib::func one() -> Int", "milliseconds": 12, "slowestExpression": 3},
           {"key": "Lib::func two()", "slowestExpression": 1}],
         "attachments": [
           {"owner": "Sources/Lib/Lib.swift", "attachedTo": "file", "milliseconds": 4},
           {"owner": "Lib::Hidden", "attachedTo": "type", "slowestExpression": 2}],
         "unmapped": {"synthesized": {"entries": 5, "milliseconds": 6},
                      "macro": {"entries": 7, "milliseconds": 8}},
         "dropped": {"build": {"entries": 9, "milliseconds": 10}, "outsideRoot": {"entries": 11, "milliseconds": 13},
                     "fileChanged": {"entries": 14, "milliseconds": 15},
                     "unscanned": {"entries": 16, "milliseconds": 17}},
         "totals": {"functionEntries": 18, "expressionEntries": 19, "milliseconds": 20},
         "changedFiles": 21, "unparsedTimingLines": 22, "escapedLines": 23, "otherWarningLines": 24,
         "warningsDropped": 25, "warningsUnmapped": 26, "pluginWarnings": 27}
        """

    /// The dead-code block: an unused production function covering a
    /// record in both runs, an entry in a test target and one outside the
    /// root, an unused local, and dead lines with a module of none.
    private static let deadCodeJSON = """
        {"version": "3.28.0",
         "runs": [{"name": "roots", "results": 3}, {"name": "production", "results": 2}],
         "declarations": [
           {"run": "roots", "ordinal": 1, "hint": "unused", "kind": "function.free", "name": "two()",
            "accessibility": "internal", "attributes": [], "modifiers": [], "ids": ["s:3Lib3twoyyF"],
            "modules": ["Lib"], "class": "production", "file": "Sources/Lib/Lib.swift", "line": 5, "column": 6,
            "place": "function", "owner": "Lib::func two()", "module": "Lib", "strippedLines": 1},
           {"run": "roots", "ordinal": 2, "hint": "redundantConformance", "hintText": "replace with: \\"P\\"",
            "kind": "var.parameter", "name": "x", "accessibility": "internal", "attributes": ["@Test"],
            "modifiers": ["final", "private"], "ids": ["s:a", "s:b"], "modules": ["LibTests"], "class": "test",
            "file": "Tests/LibTests/LibTests.swift", "line": 1, "column": 1, "place": "function",
            "owner": "LibTests::func testOne()", "module": "LibTests"},
           {"run": "roots", "ordinal": 3, "hint": "unused", "kind": "function.free", "name": "dep()",
            "accessibility": "public", "attributes": [], "modifiers": [], "ids": [], "modules": ["Dep"],
            "class": "outsideRoot", "line": 2, "column": 3, "place": "unscanned"},
           {"run": "production", "ordinal": 1, "hint": "unused", "kind": "function.free", "name": "two()",
            "accessibility": "internal", "attributes": [], "modifiers": [], "ids": ["s:3Lib3twoyyF"],
            "modules": ["Lib"], "class": "production", "file": "Sources/Lib/Lib.swift", "line": 5, "column": 6,
            "place": "function", "owner": "Lib::func two()", "module": "Lib", "strippedLines": 1},
           {"run": "production", "ordinal": 2, "hint": "unused", "kind": "var.global", "name": "second",
            "accessibility": "internal", "attributes": [], "modifiers": [], "ids": ["s:3Lib3oneSiyF6secondL_Sivp"],
            "modules": ["Lib"], "class": "local", "file": "Sources/Lib/Lib.swift", "line": 2, "column": 9,
            "place": "function", "owner": "Lib::func one() -> Int", "module": "Lib"}],
         "records": [
           {"key": "Lib::func two()", "run": "roots", "declaration": 1, "via": "usr"},
           {"key": "Lib::func two()", "run": "production", "declaration": 1, "via": "usr"}],
         "dropped": {
           "roots": {"build": 0, "fileChanged": 0, "local": 0, "outsideRoot": 1, "test": 1, "unscanned": 0},
           "production": {"build": 0, "fileChanged": 0, "local": 1, "outsideRoot": 0, "test": 0, "unscanned": 0}},
         "deadLines": {"roots": {"Lib": 1, "Other": 0}, "production": {"Lib": 1}}}
        """

    /// The index block's records, in the small library's record order,
    /// keys given by position: the first with a USR, a secondary USR and
    /// test referrers, one of them `oddReferrer`; the second a witness
    /// with no referrers; the third with a reason and no USR.
    private static let recordsJSON = """
        [{"key": "0", "usr": "s:3Lib3oneSiyF", "usrAccessor": "s:3Lib3oneSiyFig", "witness": false,
          "references": {"sameModule": 1, "otherModules": 2, "tests": 2,
                         "testReferrers": ["checks \\"one\\",\\nand more()", "testOne()"]}},
         {"key": "1", "usr": "s:3Lib3twoyyF", "witness": true,
          "references": {"sameModule": 0, "otherModules": 0, "tests": 0, "testReferrers": []}},
         {"key": "2", "reason": "inactiveIfBranch"}]
        """

    /// A hand-made history, its commit set by the caller, holding two
    /// change-coupling pairs in its order.
    private static let historyJSON = """
        {"commit": "", "date": "2027-01-15T08:00:00Z", "windowDays": 365, "windowStart": "2026-01-15T08:00:00Z",
         "mergeStyle": "linear", "commits": 7, "windowCommits": 7, "commitLog": [], "fixCommits": [],
         "revertCommits": [], "sweepCommits": [], "families": [], "warnings": [],
         "coupling": [
           {"familyA": "Lib::func one() -> Int", "fileA": "Sources/Lib/Lib.swift", "familyB": "Lib::func two()",
            "fileB": "Sources/Lib/Lib.swift", "support": 4, "changesA": 5, "changesB": 6},
           {"familyA": "Lib::func two()", "fileA": "Sources/Lib/Lib.swift", "familyB": "LibTests::func testOne()",
            "fileB": "Tests/LibTests/LibTests.swift", "support": 3, "changesA": 6, "changesB": 3}]}
        """

    /// The T1 collectors' names.
    static let names = [BuildAdapter.name, IndexAdapter.name, PeripheryAdapter.name]

    /// The hand-made build block.
    static func build() throws -> BuildReport {
        try JSONDecoder().decode(BuildReport.self, from: Data(buildJSON.utf8))
    }

    /// The hand-made dead-code block.
    static func deadCode() throws -> DeadCodeReport {
        try JSONDecoder().decode(DeadCodeReport.self, from: Data(deadCodeJSON.utf8))
    }

    /// The hand-made index block for `records`, in their order: the first
    /// with a USR, a secondary USR and test referrers, one of them
    /// `oddReferrer`; the second a witness with no referrers; the third
    /// with a reason and no USR.
    static func index(records: [FunctionRecord]) throws -> IndexReport {
        let shell = try JSONDecoder().decode(IndexReport.self, from: Data(indexJSON.utf8))
        let samples = try JSONDecoder().decode([IndexRecordUSR].self, from: Data(recordsJSON.utf8))
        let listed = zip(records, samples).map { record, sample in
            IndexRecordUSR(
                key: record.key,
                usr: sample.usr,
                usrAccessor: sample.usrAccessor,
                reason: sample.reason,
                coupling: sample.coupling
            )
        }
        return IndexReport(
            store: shell.store,
            libraryModules: shell.libraryModules,
            records: listed,
            definitions: shell.definitions,
            disagreements: shell.disagreements,
            withoutRecord: shell.withoutRecord,
            collisions: shell.collisions,
            moduleEdges: shell.moduleEdges,
            types: shell.types,
            familyReferences: shell.familyReferences,
            familyTypeReferences: shell.familyTypeReferences,
            files: shell.files
        )
    }

    /// A history at `commit` holding the hand-made coupling pairs.
    static func history(commit: String) throws -> HistoryReport {
        let shell = try JSONDecoder().decode(HistoryReport.self, from: Data(historyJSON.utf8))
        return HistoryReport(
            commit: commit,
            date: shell.date,
            windowDays: shell.windowDays,
            windowStart: shell.windowStart,
            mergeStyle: shell.mergeStyle,
            commits: shell.commits,
            windowCommits: shell.windowCommits,
            commitLog: [],
            fixCommits: [],
            revertCommits: [],
            sweepCommits: [],
            families: [],
            coupling: shell.coupling,
            warnings: []
        )
    }

    /// The options a run of collector `name` that ran records: the rules
    /// this build collects by, which a carry compares.
    static func options(_ name: String) -> [String] {
        switch name {
        case BuildAdapter.name:
            ["map: " + TimingMapper.rule, "warnings: " + WarningReader.rule]

        case IndexAdapter.name:
            IndexAdapter.options

        default:
            ["classes: " + PeripheryOutput.rule, "map: " + DeadCodeMapper.rule]
        }
    }

    /// The status of collector `name` in `state`.
    private static func status(_ name: String, _ state: CollectorState) -> CollectorStatus {
        run(name, state).status
    }

    /// The run of collector `name` in `state`: one that ran records this
    /// build's rules.
    static func run(_ name: String, _ state: CollectorState) -> CollectorRunInfo {
        CollectorRunInfo(
            name: name,
            state: state,
            reason: state == .ran ? nil : BuildAdapter.notRequestedReason,
            version: state == .ran ? "test" : nil,
            identity: nil,
            identityLabel: nil,
            options: state == .ran ? options(name) : [],
            durationMilliseconds: 0
        )
    }

    /// The small library scanned at `commit`, holding the hand-made T1
    /// results passed through the store's rows as a scan does, with its
    /// `build`, `index` and `periphery` runs ran, and a history holding
    /// the coupling pairs.
    static func snapshot(commit: String) throws -> ScannedSnapshot {
        let package = try TemporaryPackage(files)
        defer { package.remove() }
        let held = try indexed(try SnapshotHarness.scan(package, commit: commit))
        let report = held.report
            .with(history: try history(commit: commit), status: status(HistoryCollector.name, .ran))
        return ScannedSnapshot(info: held.info, report: report)
    }

    /// `scanned` holding the hand-made T1 results passed through the
    /// store's rows as a scan does, the index block's records being its
    /// own first three, with its `build`, `index` and `periphery` runs ran.
    static func indexed(_ scanned: ScannedSnapshot) throws -> ScannedSnapshot {
        let report = scanned.report
            .with(build: BuildRows.normalized(try build()), status: status(BuildAdapter.name, .ran))
            .with(
                index: IndexRows.normalized(try index(records: scanned.report.records)),
                status: status(IndexAdapter.name, .ran)
            )
            .with(deadCode: DeadCodeRows.normalized(try deadCode()), status: status(PeripheryAdapter.name, .ran))
        let info = names.reduce(scanned.info) { info, name in info.with(run: run(name, .ran)) }
        return ScannedSnapshot(info: info, report: report)
    }

    /// `snapshot` as a scan that didn't run the T1 group gives it: no T1
    /// blocks, and its three collectors skipped, not requested.
    static func plain(_ snapshot: ScannedSnapshot) -> ScannedSnapshot {
        let report = snapshot.report
            .with(build: nil, status: status(BuildAdapter.name, .skipped))
            .with(index: nil, status: status(IndexAdapter.name, .skipped))
            .with(deadCode: nil, status: status(PeripheryAdapter.name, .skipped))
        let info = names.reduce(snapshot.info) { info, name in info.with(run: run(name, .skipped)) }
        return ScannedSnapshot(info: info, report: report)
    }
}
