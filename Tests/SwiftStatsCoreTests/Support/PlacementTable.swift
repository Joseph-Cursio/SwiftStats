//
//  PlacementTable.swift
//  SwiftStatsCoreTests
//
//  Where the default placement, production records only, puts every
//  position of the Coverage and Mutation fixtures' files (M7, design §13
//  step 2b): coverage and mutation must place as they did before the build
//  added placement on every role. Each file's positions, line by line and
//  every UTF-8 column of a line plus the one past its end, are written as
//  runs: a run's first position and its place, held until the next run.
//  `Tests/Fixtures/ProductionPlacement.golden.txt` holds the table as the
//  pre-M7 `PositionPlacement` (commit fff063a) gave it.
//

import Foundation
@testable import SwiftStatsCore

/// The default placement's table over the Coverage and Mutation fixtures.
enum PlacementTable {
    /// The recorded table.
    static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("ProductionPlacement.golden.txt")

    /// The table over both fixtures, the Coverage fixture's first.
    static func text() throws -> String {
        let coverage = try MappingHarness.coverage()
        defer { coverage.remove() }
        let mutation = try MappingHarness.mutation()
        defer { mutation.remove() }
        return try table(of: coverage, titled: "Coverage") + table(of: mutation, titled: "Mutation")
    }

    /// The table of `harness`'s files, under the heading `title`.
    private static func table(of harness: MappingHarness, titled title: String) throws -> String {
        let placement = PositionPlacement(measured: harness.measured)
        var lines = ["# \(title)"]
        for file in harness.measured.files.map(\.path).sorted() {
            lines.append("## \(file)")
            let url = harness.package.root.appendingPathComponent(file)
            let text = try String(contentsOf: url, encoding: .utf8)
            var previous: String?
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for column in 1...(line.utf8.count + 1) {
                    let position = SourcePosition(line: index + 1, column: column)
                    let place = describe(placement.place(at: position, end: nil, in: file))
                    if place != previous {
                        lines.append("\(position.line):\(position.column) \(place)")
                        previous = place
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `place` as a table writes it.
    private static func describe(_ place: PositionPlacement.Place) -> String {
        switch place {
        case .record(let key):
            "record \(key)"

        case .type(let owner):
            "type \(owner)"

        case .file:
            "file"

        case .unmapped(let reason):
            "unmapped \(reason)"
        }
    }
}
