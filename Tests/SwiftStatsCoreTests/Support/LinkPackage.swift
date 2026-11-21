//
//  LinkPackage.swift
//  SwiftStatsCoreTests
//
//  A small package for tests per public function (M5), mapped from a
//  hand-written export, so the link rules' tests run without SwiftPM or
//  the coverage tools.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// A small package for tests per public function (M5): a library with a
/// concrete type's members of every kind, its conformances declared in
/// another file, a package protocol refining a standard one, protocol
/// extensions, a container subscript, free and generated functions; a
/// second library declaring protocols named like the first's types and
/// protocols; two test targets whose tests name them in different ways;
/// and a hand-written export with one entry per function, run by
/// `LibTests` except a few, and by `OtherTests` for two.
enum LinkPackage {
    /// One export entry: its file under `Sources/Lib`, without `.swift`,
    /// the text its region's braces follow, first in that file, and its name.
    private struct Entry {
        /// The file's base name.
        let file: String
        /// The text the region's braces follow.
        let marker: String
        /// The entry's name.
        let name: String
    }

    /// The libraries' files: a concrete type with members of every kind,
    /// its conformances declared in another file, a package protocol
    /// refining a standard one, protocol extensions, a container subscript,
    /// free and generated functions; in `Kit`, protocols named like `Lib`'s
    /// `Bag` and `Ring`.
    static let sources = [
        "Sources/Lib/Bag.swift": """
            public struct Bag {
                public init(items: [Int]) { self.items = items }
                public var items: [Int]
                public func grow() -> Int { items.count + 1 }
                public var total: Int { items.reduce(0, +) }
                public subscript(offset offset: Int) -> Int { items[offset] }
                public static func + (lhs: Bag, rhs: Bag) -> Bag { Bag(items: lhs.items + rhs.items) }
                func hidden() -> Int { 0 }
                public var startIndex: Int { 0 }
                public func index(after position: Int) -> Int { position + 1 }
                public func hash(into hasher: inout Hasher) { hasher.combine(items) }
                public static func == (lhs: Bag, rhs: Bag) -> Bool { lhs.items == rhs.items }
                public func index(of item: Int) -> Int? { items.firstIndex(of: item) }
                public func never() -> Int { 1 }
            }

            """,
        "Sources/Lib/Bag+Collection.swift": """
            extension Bag: Collection, Hashable {
                public var endIndex: Int { items.count }
                public subscript(position: Int) -> Int { items[position] }
            }

            """,
        "Sources/Lib/Ring.swift": """
            public protocol Ring: BidirectionalCollection {}
            public struct Loop: Ring {
                public func index(before position: Int) -> Int { position - 1 }
                public func hash(into hasher: inout Hasher) {}
            }
            extension Sequence {
                public func tally() -> Int { 0 }
            }
            extension Ring {
                public func spin() -> Int { 0 }
                public init(spun: Int) { self.init() }
                public subscript(spin spin: Int) -> Int { 0 }
            }
            public func helper() -> Int { 1 }
            public struct Box {
                public subscript(index: Int) -> Int { get { index } set {} }
            }
            public struct Plain {
                public func next() -> Int? { nil }
            }
            public func absent() -> Int { 2 }

            """,
        "Sources/Kit/Kit.swift": """
            public protocol Bag {}
            public protocol Ring: Hashable {}

            """,
        "Sources/Lib/Stub.swift": """
            // DO NOT EDIT
            public func generated() -> Int { 3 }

            """,
        "Tests/LibTests/BagTests.swift": """
            @Test func growsByName() {
                #expect(thing.grow() == 1)
            }

            """,
        "Tests/LibTests/MiscTests.swift": """
            @Test func growsWithType() {
                let bag = Bag(items: [1])
                #expect(bag.grow() == 2)
                #expect(bag.total == 1)
                #expect(bag[offset: 0] == 1)
                #expect((bag + bag).items.count == 2)
                #expect(bag.index(of: 1) == 0)
                #expect(bag.startIndex == 0)
            }

            @Test func growsWithoutType() {
                #expect(thing.grow() == 1)
                #expect(helper() == 1)
                #expect([1].tally() == 0)
                #expect(Loop().spin() == 0)
                var box = Box()
                box[0] = 1
            }

            @Test func spinsRing() {
                let loop: some Ring = Loop(spun: 1)
                #expect(loop[spin: 0] == 0)
            }

            """,
        "Tests/OtherTests/OtherTests.swift": """
            @Test func otherGrow() {
                let bag = Bag(items: [])
                #expect(bag.grow() == 1)
                #expect(helper() == 1)
            }

            """
    ]

    /// The entries of the export.
    private static let entries: [Entry] = [
        Entry(file: "Bag", marker: "init(", name: "init"),
        Entry(file: "Bag", marker: "func grow", name: "grow"),
        Entry(file: "Bag", marker: "var total", name: "total"),
        Entry(file: "Bag", marker: "offset offset", name: "offset"),
        Entry(file: "Bag", marker: "func +", name: "plus"),
        Entry(file: "Bag", marker: "func hidden", name: "hidden"),
        Entry(file: "Bag", marker: "var startIndex", name: "startIndex"),
        Entry(file: "Bag", marker: "index(after", name: "after"),
        Entry(file: "Bag", marker: "func hash", name: "hash"),
        Entry(file: "Bag", marker: "func ==", name: "equal"),
        Entry(file: "Bag", marker: "index(of", name: "indexOf"),
        Entry(file: "Bag", marker: "func never", name: "never"),
        Entry(file: "Bag+Collection", marker: "var endIndex", name: "endIndex"),
        Entry(file: "Bag+Collection", marker: "subscript(position", name: "position"),
        Entry(file: "Ring", marker: "index(before", name: "before"),
        Entry(file: "Ring", marker: "func hash", name: "loopHash"),
        Entry(file: "Ring", marker: "func tally", name: "tally"),
        Entry(file: "Ring", marker: "func spin", name: "spin"),
        Entry(file: "Ring", marker: "init(spun", name: "spun"),
        Entry(file: "Ring", marker: "spin spin", name: "spinAt"),
        Entry(file: "Ring", marker: "func helper", name: "helper"),
        Entry(file: "Ring", marker: "get {", name: "boxGet"),
        Entry(file: "Ring", marker: "set {", name: "boxSet"),
        Entry(file: "Ring", marker: "func next", name: "next"),
        Entry(file: "Stub", marker: "func generated", name: "generated")
    ]

    /// The entries no test process ran.
    private static let unrun: Set<String> = ["never", "boxGet", "next"]
    /// The entries `OtherTests`' process ran.
    private static let otherRan: Set<String> = ["init", "helper"]

    /// The real path of `url`.
    private static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else {
            return url.path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The export's region of the braces that follow `marker`'s first
    /// occurrence in `text`: its line and the 1-based columns of its braces.
    private static func region(
        in text: String,
        after marker: String
    ) throws -> (line: Int, columns: ClosedRange<Int>) {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
        let line = try #require(rows.firstIndex { $0.contains(marker) })
        let row = Array(rows[line].utf8)
        let markerBytes = Array(marker.utf8)
        let found = try #require(row.indices.first { Array(row[$0...].prefix(markerBytes.count)) == markerBytes })
        let open = try #require(row.indices.first { $0 >= found && row[$0] == UInt8(ascii: "{") })
        var depth = 0
        for index in open..<row.count {
            depth += row[index] == UInt8(ascii: "{") ? 1 : (row[index] == UInt8(ascii: "}") ? -1 : 0)
            if depth == 0 {
                return (line + 1, (open + 1)...(index + 1))
            }
        }
        throw CocoaError(.formatting)
    }

    /// The package, written to a temporary directory.
    private static func package() throws -> TemporaryPackage {
        try TemporaryPackage(sources, targets: [
            DescribedTarget(
                name: "Kit",
                type: "library",
                moduleType: "SwiftTarget",
                path: "Sources/Kit",
                sources: ["Kit.swift"]
            ),
            DescribedTarget(
                name: "Lib",
                type: "library",
                moduleType: "SwiftTarget",
                path: "Sources/Lib",
                sources: ["Bag+Collection.swift", "Bag.swift", "Ring.swift", "Stub.swift"]
            ),
            DescribedTarget(
                name: "LibTests",
                type: "test",
                moduleType: "SwiftTarget",
                path: "Tests/LibTests",
                sources: ["BagTests.swift", "MiscTests.swift"]
            ),
            DescribedTarget(
                name: "OtherTests",
                type: "test",
                moduleType: "SwiftTarget",
                path: "Tests/OtherTests",
                sources: ["OtherTests.swift"]
            )
        ])
    }

    /// The export of the package at `root`, its real path.
    private static func export(root: String) throws -> CoverageExport {
        var functions: [String] = []
        for entry in entries {
            let text = try #require(sources["Sources/Lib/\(entry.file).swift"])
            let (line, columns) = try region(in: text, after: entry.marker)
            let count = unrun.contains(entry.name) ? 0 : 1
            functions.append("""
                {"name":"\(entry.name)","count":\(count),"filenames":["\(root)/Sources/Lib/\(entry.file).swift"],\
                "regions":[[\(line),\(columns.lowerBound),\(line),\(columns.upperBound + 1),\(count),0,0,0]]}
                """)
        }
        let files = ["Bag", "Bag+Collection", "Ring", "Stub"]
            .map { #"{"filename":"\#(root)/Sources/Lib/\#($0).swift","segments":[]}"# }
        let text = #"{"data":[{"files":[\#(files.joined(separator: ","))],"#
            + #""functions":[\#(functions.joined(separator: ","))]}],"#
            + #""type":"llvm.coverage.json.export","version":"3.0.1"}"#
        return try CoverageExport.decode(Data(text.utf8))
    }

    /// The profiles of a passing run: `LibTests` ran every entry but the
    /// unrun ones, `OtherTests` two.
    private static func profiles() -> CoverageProfiles {
        let ran = entries.map(\.name).filter { unrun.contains($0) == false }
        return CoverageProfiles(
            export: URL(fileURLWithPath: "/dev/null"),
            bundles: ["LibTests", "OtherTests"],
            testStatus: 0,
            hasExtraProfiles: false,
            counts: [
                "LibTests": Dictionary(uniqueKeysWithValues: ran.map { ($0, Int64(1)) }),
                "OtherTests": Dictionary(uniqueKeysWithValues: otherRan.map { ($0, Int64(1)) })
            ]
        )
    }

    /// The package's coverage, mapped.
    static func report() throws -> CoverageReport {
        let package = try package()
        defer { package.remove() }
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        let measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
        let mapper = CoverageMapper(measured: measured, targets: targets, root: package.root, excluded: [])
        return mapper.report(of: try export(root: realPath(package.root)), profiles: profiles()) { _ in [:] }
    }
}
