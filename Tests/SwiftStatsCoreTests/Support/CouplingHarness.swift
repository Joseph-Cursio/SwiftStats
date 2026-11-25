//
//  CouplingHarness.swift
//  SwiftStatsCoreTests
//
//  The Index fixture's coupling built straight from its recorded index
//  (M7, design §4, §13 step 5b), without a scan: a measured copy of the
//  fixture (`BuildFixture`), `reader.json` read through
//  `RecordedIndexSource` with the copy's paths put back, walked with the
//  recorded describe, joined to the copy's records, and the reference
//  graph's input and the coupling made from that, so a test can ask for
//  one reference's container or one declaration's owner.
//  Nothing is built or run.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The Index fixture's coupling, from its recording.
struct CouplingHarness {
    /// The measured copy.
    let fixture: BuildFixture
    /// The recording as walked.
    let snapshot: IndexSnapshot
    /// What the reference graph reads.
    let input: ReferenceGraph.Input
    /// The resolver of containers and targets over `input`.
    let resolver: ReferenceResolver
    /// The graph over `input`.
    let graph: ReferenceGraph
    /// The coupling as the `index` block writes it.
    let coupling: IndexCoupling

    /// The harness over the recording.
    init() throws {
        let copy = try BuildFixture()
        do {
            let package = try JSONDecoder().decode(DescribedPackage.self, from: IndexFixture.data("describe.json"))
            let source = try RecordedIndexSource(
                recording: IndexFixture.data("reader.json"),
                restoring: IndexFixtureScan.restoring(copy)
            )
            let filter = try UnitFilter(root: copy.root, scratch: copy.build, package: package)
            let walked = try IndexWalk.walk(source, filter: filter)
            let measured = copy.measured
            let files = Set(measured.files.map(\.path))
            let join = USRJoin(snapshot: walked, records: measured.records, files: files, changedFiles: [])
            let scan = IndexAdapter.Scan(
                root: copy.package.root,
                records: measured.records,
                types: measured.types,
                files: measured.files,
                targets: copy.targets,
                topLevelLines: measured.topLevelLines,
                fileScopedTypes: measured.fileScopedTypes,
                warnings: measured.warnings
            )
            fixture = copy
            snapshot = walked
            input = IndexCoupling.input(snapshot: walked, join: join, scan: scan, joinable: files)
            resolver = ReferenceResolver(input)
            graph = ReferenceGraph(input)
            coupling = IndexCoupling(
                snapshot: walked,
                join: join,
                scan: scan,
                joinable: files,
                packageTargets: Set(filter.modules.values)
            )
        } catch {
            copy.remove()
            throw error
        }
    }

    /// The reference to `usr` in `file` at `line` and `column`.
    func reference(to usr: String, in file: String, at line: Int, _ column: Int) throws -> OccurrenceFacts.Located {
        try #require(input.facts.references.first { located in
            located.file == file && located.occurrence.usr == usr
                && located.occurrence.line == line && located.occurrence.column == column
        }, "no reference to \(usr) at \(file):\(line):\(column)")
    }

    /// The primary USR of the record keyed `key`.
    func usr(of key: String) throws -> String {
        try #require(input.join.primary[key], "no USR for \(key)")
    }

    /// Removes the copy.
    func remove() {
        fixture.remove()
    }
}
