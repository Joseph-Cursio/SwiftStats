import Foundation
@testable import SwiftStatsCore
import Testing

/// Placing positions on records, types and files (M5, M6): coverage
/// gives a region's start and end, mutation an anchor with no end.
@Suite("Position placement")
struct PositionPlacementTests {
    /// A function, a type with a stored property and a method, and a global.
    private static let source = """
        public func first() -> Int {
            1
        }
        public struct Holder {
            public var value = 0
            public func get() -> Int { value }
        }
        let global = 3

        """

    @Test(
        "a position goes to the innermost record holding it, else its type, else its file; only an end unmaps it"
    )
    func places() throws {
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": Self.source])
        defer { package.remove() }
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        let measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
        let placement = PositionPlacement(measured: measured)
        let file = "Sources/Lib/Lib.swift"
        let first = try #require(measured.records.first { $0.name == "first" }).key
        let get = try #require(measured.records.first { $0.name == "get" }).key
        let place = { (line: Int, column: Int, end: SourcePosition?) in
            placement.place(at: SourcePosition(line: line, column: column), end: end, in: file)
        }

        #expect(place(2, 5, nil) == .record(first))
        #expect(place(2, 5, SourcePosition(line: 2, column: 6)) == .record(first))
        #expect(place(2, 5, SourcePosition(line: 5, column: 1)) == .unmapped(PositionPlacement.pastRecord))
        #expect(place(6, 32, nil) == .record(get))
        #expect(place(5, 24, nil) == .type("Lib::Holder"))
        #expect(place(8, 14, nil) == .file)
    }
}
