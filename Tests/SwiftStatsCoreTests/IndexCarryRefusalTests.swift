import Foundation
@testable import SwiftStatsCore
import Testing

/// Why held T1 results don't carry onto a rescan (M7, design §9.4), on
/// hand-made snapshots of a small package: the first failing condition of
/// commit, tree, rules, records, types and files is named, and each kind of
/// record, type and file change is caught, a start column, a family and an
/// owning type among them.
@Suite("Index carry refusals")
struct IndexCarryRefusalTests {
    @Test("""
        when several conditions fail, the refusal names the first of commit, tree, rules, records, types and files, \
        with the build's rules before the index's and outskirts'
        """)
    func refusalOrder() throws {
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let held = try IndexCarrySamples.held(of: try IndexCarrySamples.held(plain))
        let open = try IndexCarrySamples.record("open", in: plain)
        let moved = IndexCarrySamples.records(of: plain, changing: open.key) { record in
            IndexCarrySamples.changing(record, column: record.range.start.column + 1, parentKey: nil, typePath: nil)
        }
        let otherTypes = plain.report.types.map(IndexCarrySamples.lengthened)
        let otherFiles = plain.report.files.map { file in
            FileRecord(
                path: file.path,
                module: file.module,
                lines: file.lines,
                strippedLines: file.strippedLines,
                generated: file.generated,
                sha256: "other"
            )
        }
        let rules = [
            IndexCarrySamples.ran(IndexAdapter.name, options: ["usr: an older rule"]),
            IndexCarrySamples.ran(PeripheryAdapter.name, options: ["classes: an older rule"])
        ]
        let olderBuild = IndexCarrySamples.ran(BuildAdapter.name, options: ["map: " + TimingMapper.rule])
        let refusal = { (held: HeldIndex) in
            IndexCarrySamples.refusal(of: held, onto: plain, records: moved, types: otherTypes, files: otherFiles)
        }

        let outside = IndexCarrySamples.replacing(git: .outsideGit, in: held)
        let dirty = IndexCarrySamples.replacing(git: IndexCarrySamples.dirty("aaa"), in: held)
        let allRules = IndexCarrySamples.replacing(runs: rules + [olderBuild], in: held)
        let readerRules = IndexCarrySamples.replacing(runs: rules, in: held)
        let periphery = IndexCarrySamples.replacing(runs: [rules[1]], in: held)

        #expect(refusal(outside) == "no git commit to compare against")
        #expect(refusal(dirty) == "the uncommitted changes differ")
        #expect(refusal(allRules) == "`build` was collected under another `warnings:` rule")
        #expect(refusal(readerRules) == "`index` was collected under another `units:` rule")
        #expect(refusal(periphery) == "`periphery` was collected under another `classes:` rule")
        #expect(refusal(held) == "`\(open.key)` spans other lines or columns now")
        let records = plain.report.records
        #expect(IndexCarrySamples.refusal(of: held, onto: plain, records: records, types: otherTypes, files: otherFiles)
            == "type `Box` in `\(IndexCarrySamples.libPath)` spans other lines or columns now")
        let types = plain.report.types
        #expect(IndexCarrySamples.refusal(of: held, onto: plain, records: records, types: types, files: otherFiles)
            == "`\(IndexCarrySamples.libPath)` holds other bytes now")
        let files = plain.report.files
        #expect(IndexCarrySamples.refusal(of: held, onto: plain, records: records, types: types, files: files) == nil)
    }

    @Test("""
        a rescan of the same tree is refused when a record's start column, family, owning type or file changed, or \
        a record is gone or new, naming the first key in order
        """)
    func otherRecords() throws {
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let held = try IndexCarrySamples.held(of: try IndexCarrySamples.held(plain))
        let open = try IndexCarrySamples.record("open", in: plain)
        let inner = try IndexCarrySamples.record("inner", in: plain)
        let two = try IndexCarrySamples.record("two", in: plain)
        let refusal = { (records: [FunctionRecord]) in
            IndexCarrySamples.refusal(
                of: held,
                onto: plain,
                records: records,
                types: plain.report.types,
                files: plain.report.files
            )
        }
        let column = IndexCarrySamples.records(of: plain, changing: two.key) { record in
            IndexCarrySamples.changing(record, column: record.range.start.column + 1, parentKey: nil, typePath: nil)
        }
        let family = IndexCarrySamples.records(of: plain, changing: inner.key) { record in
            IndexCarrySamples.changing(record, column: nil, parentKey: .some(nil), typePath: nil)
        }
        let owner = IndexCarrySamples.records(of: plain, changing: open.key) { record in
            IndexCarrySamples.changing(record, column: nil, parentKey: nil, typePath: "Crate")
        }
        let added = FunctionRecord(
            key: two.key + "2",
            module: two.module,
            kind: two.kind,
            name: two.name,
            accessorKind: nil,
            file: two.file,
            range: two.range,
            strippedLines: two.strippedLines,
            bodyLines: two.bodyLines,
            parameterCount: two.parameterCount,
            isDocumented: two.isDocumented,
            isAsync: two.isAsync,
            bodyHash: two.bodyHash,
            parentKey: nil,
            ifConfig: nil,
            role: two.role,
            access: two.access
        )

        #expect(inner.parentKey == open.key && open.typePath == "Box")
        #expect(refusal(column) == "`\(two.key)` spans other lines or columns now")
        #expect(refusal(family) == "`\(inner.key)` belongs to another family now")
        #expect(refusal(owner) == "`\(open.key)` belongs to another type now")
        #expect(refusal(plain.report.records.filter { $0.key != two.key }) == "`\(two.key)` names no record now")
        #expect(refusal(plain.report.records + [added]) == "`\(two.key)2` has no index results")
    }

    @Test("""
        a rescan of the same tree is refused when a type record is gone, new or over another span, or a file is \
        scanned now that wasn't, isn't scanned any more, or holds other bytes
        """)
    func otherTypesAndFiles() throws {
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let held = try IndexCarrySamples.held(of: try IndexCarrySamples.held(plain))
        let box = try #require(plain.report.types.first)
        let lib = try #require(plain.report.files.first { $0.path == IndexCarrySamples.libPath })
        let extra = FileRecord(
            path: "Sources/Lib/Extra.swift",
            module: "Lib",
            lines: 1,
            strippedLines: 0,
            generated: false,
            sha256: "abc"
        )
        let types = { (types: [TypeRecord]) in
            IndexCarrySamples.refusal(
                of: held,
                onto: plain,
                records: plain.report.records,
                types: types,
                files: plain.report.files
            )
        }
        let files = { (files: [FileRecord]) in
            IndexCarrySamples.refusal(
                of: held,
                onto: plain,
                records: plain.report.records,
                types: plain.report.types,
                files: files
            )
        }

        #expect(plain.report.types.count == 1 && box.name == "Box")
        #expect(types([]) == "type `Box` in `\(IndexCarrySamples.libPath)` is gone now")
        #expect(types([box, box]) == "type `Box` in `\(IndexCarrySamples.libPath)` has no index results")
        #expect(types([IndexCarrySamples.lengthened(box)])
            == "type `Box` in `\(IndexCarrySamples.libPath)` spans other lines or columns now")
        #expect(files(plain.report.files + [extra])
            == "`Sources/Lib/Extra.swift` is scanned now, but wasn't when the index was built")
        #expect(files(plain.report.files.filter { $0.path != lib.path }) == "`\(lib.path)` isn't scanned now")
    }
}
