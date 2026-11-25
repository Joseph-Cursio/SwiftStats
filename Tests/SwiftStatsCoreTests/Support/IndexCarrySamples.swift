//
//  IndexCarrySamples.swift
//  SwiftStatsCoreTests
//
//  Snapshots holding T1 results that a rescan of the same tree carries, as
//  the T1 carry tests use them (M7, design §9.4): a small package with a
//  type, a method holding a local function and a free function, given the
//  hand-made build, index and dead-code blocks (`IndexStoreSamples`) with
//  the index's file hashes made the scan's own and a compiler warning as a
//  `swiftc` finding; the held results a store reads back for them; records
//  and types changed one way at a time; and the refusal a rescan gets.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Snapshots of a small package with and without carried T1 results.
enum IndexCarrySamples {
    /// The package: a struct whose method holds a local function, a free
    /// function and a test.
    static let files = [
        "Sources/Lib/Lib.swift": """
            public struct Box {
                public func open() -> Int {
                    func inner() -> Int { 1 }
                    return inner()
                }
            }

            func two() {}

            """,
        "Tests/LibTests/LibTests.swift": "func testOne() {\n    _ = Box().open()\n}\n"
    ]
    /// The library's file.
    static let libPath = "Sources/Lib/Lib.swift"
    /// A clean git state at `c1`.
    static let clean = SnapshotHarness.git(commit: "c1")
    /// The line `two()` is declared on.
    static let twoLine = 8
    /// The column `two()`'s name starts at.
    static let twoColumn = 6
    /// The compiler warning the held snapshot holds, on `two()`.
    static let warning = Finding(
        tool: WarningReader.tool,
        rule: "unused_result",
        category: "warning",
        kind: .defect,
        severity: "warning",
        message: "result unused",
        symbol: nil,
        locations: [FindingLocation(file: libPath, line: twoLine, column: twoColumn, attachedTo: .file, owner: nil)]
    )
    /// The build's warning describing its results, which a carry keeps.
    static let buildWarning = ScanWarning(file: nil, message: "build: 1 file changed during the scan; …")

    /// The harness date `days` days later.
    static func later(_ days: TimeInterval) -> Date {
        SnapshotHarness.date + days * CarrySamples.day
    }

    /// A git state at `c1` with uncommitted changes hashed as `hash`.
    static func dirty(_ hash: String) -> GitState {
        GitState(commit: "c1", branch: nil, isDirty: true, dirtyHash: hash, packagePath: "")
    }

    /// The package with `files` replacing some of its files, scanned at
    /// `git` on `date` as the test build, without history and the T1
    /// group not run.
    static func scan(git: GitState, files changed: [String: String], date: Date) throws -> ScannedSnapshot {
        let package = try TemporaryPackage(files.merging(changed) { $1 })
        defer { package.remove() }
        return try SnapshotScanner(
            scanner: PackageScanner(describer: package.describer, tools: SnapshotHarness.noTools),
            build: SnapshotHarness.build
        )
        .scan(
            packageAt: package.root,
            configurationFile: nil,
            git: git,
            toolchain: SnapshotHarness.toolchain,
            date: date,
            history: .skipped("test")
        )
    }

    /// The package scanned at `git` on `date`, the T1 group not run.
    static func scan(git: GitState, date: Date) throws -> ScannedSnapshot {
        try scan(git: git, files: [:], date: date)
    }

    /// `scanned` holding T1 results that describe it: the hand-made blocks
    /// with the index listing every record, as a scan's does, and the
    /// scan's own file hashes, its build's warning and the compiler
    /// warning, its three runs ran by this build's rules.
    static func held(_ scanned: ScannedSnapshot) throws -> ScannedSnapshot {
        let indexed = try IndexStoreSamples.indexed(scanned)
        let index = try #require(indexed.report.index)
        let listed = Dictionary(index.records.map { ($0.key, $0) }) { first, _ in first }
        let hashed = IndexReport(
            store: index.store,
            libraryModules: index.libraryModules,
            records: scanned.report.records.map { record in
                listed[record.key]
                    ?? IndexRecordUSR(key: record.key, usr: nil, usrAccessor: nil, reason: nil, coupling: nil)
            },
            definitions: index.definitions,
            disagreements: index.disagreements,
            withoutRecord: index.withoutRecord,
            collisions: index.collisions,
            moduleEdges: index.moduleEdges,
            types: index.types,
            familyReferences: index.familyReferences,
            familyTypeReferences: index.familyTypeReferences,
            files: scanned.report.files.map { IndexFileHash(path: $0.path, sha256: $0.sha256) }
        )
        let status = try #require(indexed.report.collectors.first { $0.name == IndexAdapter.name })
        let report = indexed.report.with(index: IndexRows.normalized(hashed), status: status)
            .with(findings: [warning], of: WarningReader.tool)
            .with(warnings: [buildWarning])
        return ScannedSnapshot(info: indexed.info, report: report)
    }

    /// The held T1 results `snapshot` gives once stored, read back as a
    /// rescan reads them.
    static func held(of snapshot: ScannedSnapshot) throws -> HeldIndex {
        let made = try TemporaryStore("IndexCarry")
        defer { made.remove() }
        let id = try made.store.save(snapshot)
        return try #require(try made.store.heldIndex(id: id))
    }

    /// `held` with `runs` replacing its runs of the same names.
    static func replacing(runs: [CollectorRunInfo], in held: HeldIndex) -> HeldIndex {
        let run = { (old: CollectorRunInfo) in runs.first { $0.name == old.name } ?? old }
        return HeldIndex(
            git: held.git,
            build: run(held.build),
            readers: held.readers.map(run),
            collectedAt: held.collectedAt,
            buildReport: held.buildReport,
            index: held.index,
            deadCode: held.deadCode,
            findings: held.findings,
            warnings: held.warnings,
            records: held.records,
            types: held.types,
            files: held.files
        )
    }

    /// `held` at `git`.
    static func replacing(git: GitState, in held: HeldIndex) -> HeldIndex {
        HeldIndex(
            git: git,
            build: held.build,
            readers: held.readers,
            collectedAt: held.collectedAt,
            buildReport: held.buildReport,
            index: held.index,
            deadCode: held.deadCode,
            findings: held.findings,
            warnings: held.warnings,
            records: held.records,
            types: held.types,
            files: held.files
        )
    }

    /// A run of collector `name` that ran with `options`.
    static func ran(_ name: String, options: [String]) -> CollectorRunInfo {
        CollectorRunInfo(
            name: name,
            state: .ran,
            reason: nil,
            version: "test",
            identity: nil,
            identityLabel: nil,
            options: options,
            durationMilliseconds: 0
        )
    }

    /// `record` with its start moved to `column`, or its parent or owning
    /// type replaced when given.
    static func changing(
        _ record: FunctionRecord,
        column: Int?,
        parentKey: String??,
        typePath: String??
    ) -> FunctionRecord {
        let start = SourcePosition(line: record.range.start.line, column: column ?? record.range.start.column)
        var changed = FunctionRecord(
            key: record.key,
            module: record.module,
            kind: record.kind,
            name: record.name,
            accessorKind: record.accessorKind,
            file: record.file,
            range: SourceSpan(start: start, end: record.range.end),
            strippedLines: record.strippedLines,
            bodyLines: record.bodyLines,
            parameterCount: record.parameterCount,
            isDocumented: record.isDocumented,
            isAsync: record.isAsync,
            bodyHash: record.bodyHash,
            parentKey: parentKey ?? record.parentKey,
            ifConfig: record.ifConfig,
            role: record.role,
            access: record.access
        )
        changed.complexity = record.complexity
        changed.typePath = typePath ?? record.typePath
        changed.typeFile = record.typeFile
        changed.effect = record.effect
        return changed
    }

    /// `type` ending one line lower.
    static func lengthened(_ type: TypeRecord) -> TypeRecord {
        TypeRecord(
            module: type.module,
            kind: type.kind,
            name: type.name,
            file: type.file,
            range: SourceSpan(
                start: type.range.start,
                end: SourcePosition(line: type.range.end.line + 1, column: type.range.end.column)
            ),
            strippedLines: type.strippedLines,
            memberCount: type.memberCount,
            isLocal: type.isLocal,
            ifConfig: type.ifConfig,
            conformances: type.conformances
        )
    }

    /// The record named `name` in `snapshot`.
    static func record(_ name: String, in snapshot: ScannedSnapshot) throws -> FunctionRecord {
        try #require(snapshot.report.records.first { $0.name == name })
    }

    /// `snapshot`'s records with the one keyed `key` replaced by what
    /// `change` makes of it.
    static func records(
        of snapshot: ScannedSnapshot,
        changing key: String,
        by change: (FunctionRecord) -> FunctionRecord
    ) -> [FunctionRecord] {
        snapshot.report.records.map { $0.key == key ? change($0) : $0 }
    }

    /// Why `held` can't be carried onto a scan at `snapshot`'s git state
    /// whose records, types and files are `records`, `types` and `files`.
    static func refusal(
        of held: HeldIndex,
        onto snapshot: ScannedSnapshot,
        records: [FunctionRecord],
        types: [TypeRecord],
        files: [FileRecord]
    ) -> String? {
        IndexCarry.refusal(of: held, git: snapshot.info.git, records: records, types: types, files: files)
    }

    /// A run of collector `name` that ended as `state` for `reason`,
    /// recording `options`, in `milliseconds`.
    static func ended(
        _ name: String,
        _ state: CollectorState,
        reason: String,
        options: [String],
        milliseconds: Int
    ) -> CollectorRunInfo {
        CollectorRunInfo(
            name: name,
            state: state,
            reason: reason,
            version: nil,
            identity: nil,
            identityLabel: nil,
            options: options,
            durationMilliseconds: milliseconds
        )
    }

    /// `snapshot` as a scan whose build ended as `run` says, without build
    /// results.
    static func withBuild(_ run: CollectorRunInfo, in snapshot: ScannedSnapshot) -> ScannedSnapshot {
        ScannedSnapshot(
            info: snapshot.info.with(run: run),
            report: snapshot.report.with(build: nil, status: run.status)
        )
    }

    /// The refusal of a rescan of the snapshot of the package at `c1`,
    /// whose T1 results were collected on the harness date, for `reason`.
    static func refused(_ reason: String, package: String) -> StoreError {
        .indexNotKept(
            snapshot: "\(package) at c1",
            collectedAt: SnapshotScanner.format(SnapshotHarness.date),
            reason: reason
        )
    }
}
