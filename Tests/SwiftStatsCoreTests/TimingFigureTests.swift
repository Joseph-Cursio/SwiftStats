//
//  TimingFigureTests.swift
//  SwiftStatsCoreTests
//
//  The timing mapper's classes and figures on hand-written entries (M7,
//  design §6.2): entries left out by class, paths compared in NFC, whole
//  milliseconds rounded once after summing in hundredths, attachments,
//  totals that leave out records nested in a body, and a local type's
//  members, which are not (`TimingFigureTests+Saturation` checks figures
//  at the top of an `Int`).
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The timing mapper's figures, on a small library and hand-written
/// entries.
@Suite("Timing figures")
struct TimingFigureTests {
    /// A package, measured.
    struct Library {
        /// The package.
        let package: TemporaryPackage
        /// Its measurements.
        let measured: ScanMeasurements
        /// Its root, as its real path.
        let root: String

        /// A mapper onto the package, nothing changed.
        var mapper: TimingMapper {
            mapper(changedFiles: [])
        }

        /// `package`, measured.
        init(_ package: TemporaryPackage) throws {
            self.package = package
            let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
            measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
            root = BuildFixture.realPath(package.root)
        }

        /// A mapper onto the package, the files `changedFiles` changed.
        func mapper(changedFiles: Set<String>) -> TimingMapper {
            TimingMapper(
                measured: measured,
                root: root,
                build: root + "/.swiftstats/index-build",
                changedFiles: changedFiles
            )
        }
    }

    /// A small library: three one-line functions, a function with a local
    /// function, a type with a stored property and a subscript with
    /// explicit accessors, a global with an initialiser, and a function
    /// declaring a local type with a stored property and a method.
    private static let source = """
        public func first() -> Int { 1 }
        public func second() -> Int { 2 }
        public func third() -> Int { 3 }
        public func outer() -> Int {
            func inner() -> Int { 1 }
            return inner()
        }
        public struct Box {
            public var stored = 1
            public subscript(index: Int) -> Int {
                get { index }
                set { _ = newValue }
            }
        }
        let global = [1, 2].map { $0 }
        public func shaped() -> Int {
            struct Square {
                let side = 2
                func area() -> Int { side * side }
            }
            return Square().area()
        }

        """
    /// The small library's file.
    private static let file = "Sources/Lib/Lib.swift"
    /// Half of `Int.max` hundredths, rounded up: two of them pass it by
    /// one.
    static let halfMaximal = Int.max / 2 + 1
    /// `Int.max` hundredths (92233720368547758.07 ms) in whole
    /// milliseconds.
    static let maximalMilliseconds = 92_233_720_368_547_758

    /// The small library, measured.
    static func library() throws -> Library {
        try Library(TemporaryPackage([file: source]))
    }

    /// An entry of `kind` taking `hundredths` at `line` and `column` of
    /// the small library's file under `root`.
    static func entry(
        _ kind: TimingEntry.Kind,
        _ hundredths: Int,
        line: Int,
        column: Int,
        root: String
    ) -> TimingEntry {
        TimingEntry(
            kind: kind,
            hundredths: hundredths,
            place: BuildPlace(path: root + "/" + file, line: line, column: column),
            declaration: nil
        )
    }
    @Test("entries are classed synthesized, macro, build, outside the root, file changed or unscanned, then placed")
    func classes() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let root = library.root
        let mapper = library.mapper
        let changed = library.mapper(changedFiles: [Self.file])
        let entryAt = { (path: String) in
            TimingEntry(
                kind: .function,
                hundredths: 1,
                place: BuildPlace(path: path, line: 1, column: 13),
                declaration: "f"
            )
        }
        #expect(mapper.place(TimingEntry(kind: .function, hundredths: 1, place: nil, declaration: "f")) == .synthesized)
        #expect(mapper.place(entryAt("@__swiftmacro_3Lib4TestfMp_.swift")) == .macro)
        #expect(mapper.place(entryAt(root + "/.swiftstats/index-build/checkouts/Dep/Dep.swift")) == .build)
        #expect(mapper.place(entryAt("/elsewhere/Dep/Dep.swift")) == .outsideRoot)
        #expect(mapper.place(entryAt(root + "-sibling/Sources/Lib/Lib.swift")) == .outsideRoot)
        #expect(mapper.place(entryAt(root + "/Sources/Lib/Other.swift")) == .unscanned("Sources/Lib/Other.swift"))
        #expect(changed.place(entryAt(root + "/" + Self.file)) == .fileChanged(Self.file))
        #expect(mapper.place(entryAt(root + "/" + Self.file)) == .record("Lib::func first() -> Int"))
    }

    @Test("a path the compiler spells decomposed finds the file the scan spelled composed")
    func normalisedPaths() throws {
        let files = ["Sources/Lib/Caf\u{E9}.swift": "public func cafe() -> Int { 1 }\n"]
        let library = try Library(TemporaryPackage(files))
        defer { library.package.remove() }
        let root = library.root
        let mapper = library.mapper
        let decomposed = TimingEntry(
            kind: .function,
            hundredths: 1,
            place: BuildPlace(path: root + "/Sources/Lib/Cafe\u{301}.swift", line: 1, column: 13),
            declaration: "f"
        )
        #expect(mapper.place(decomposed) == .record("Lib::func cafe() -> Int"))
    }

    @Test("figures are summed in hundredths and rounded once, half up: 0.40 + 0.40 is 1, 0.49 is 0, 0.50 is 1")
    func rounding() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let root = library.root
        let mapper = library.mapper
        let mapped = mapper.map([
            Self.entry(.function, 40, line: 1, column: 13, root: root),
            Self.entry(.function, 40, line: 1, column: 13, root: root),
            Self.entry(.expression, 49, line: 1, column: 30, root: root),
            Self.entry(.function, 49, line: 2, column: 13, root: root),
            Self.entry(.function, 50, line: 3, column: 13, root: root)
        ])
        #expect(mapped.records == [
            BuildRecordTiming(key: "Lib::func first() -> Int", milliseconds: 1, slowestExpression: 0),
            BuildRecordTiming(key: "Lib::func second() -> Int", milliseconds: 0, slowestExpression: nil),
            BuildRecordTiming(key: "Lib::func third() -> Int", milliseconds: 1, slowestExpression: nil)
        ])
        // 0.80 + 0.49 + 0.50 = 1.79.
        #expect(mapped.totals.milliseconds == 2)
    }

    @Test("a local function's entry stays on its record and out of the totals; a subscript accessor's counts")
    func nestedTotals() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let root = library.root
        let mapper = library.mapper
        let measured = library.measured
        let mapped = mapper.map([
            Self.entry(.function, 120, line: 4, column: 13, root: root),
            Self.entry(.function, 60, line: 5, column: 10, root: root),
            Self.entry(.function, 20, line: 11, column: 9, root: root)
        ])
        let inner = try #require(measured.records.first { $0.name == "inner" }).key
        let getter = try #require(measured.records.first { $0.accessorKind == "get" }).key
        #expect(mapped.records.first { $0.key == inner }?.milliseconds == 1)
        #expect(mapped.records.first { $0.key == getter }?.milliseconds == 0)
        // 1.20 + 0.20, the local function's 0.60 already inside `outer`'s.
        #expect(mapped.totals.milliseconds == 1)
        #expect(TimingMapper.nestedInBody(measured.records, types: measured.types) == [inner])
    }

    @Test("a local type's member counts in the totals, and its stored property's time goes to the local type")
    func localTypeTotals() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let root = library.root
        let mapped = library.mapper.map([
            Self.entry(.function, 100, line: 16, column: 13, root: root),
            Self.entry(.function, 60, line: 18, column: 13, root: root),
            Self.entry(.expression, 20, line: 18, column: 20, root: root),
            Self.entry(.function, 140, line: 19, column: 14, root: root)
        ])
        let area = try #require(library.measured.records.first { $0.name == "area" }).key
        #expect(mapped.records == [
            BuildRecordTiming(key: "Lib::func shaped() -> Int", milliseconds: 1, slowestExpression: nil),
            BuildRecordTiming(key: area, milliseconds: 1, slowestExpression: nil)
        ])
        #expect(mapped.attachments == [
            BuildAttachment(owner: "Lib::Square", attachedTo: .type, milliseconds: 1, slowestExpression: 0)
        ])
        // 1.00 + 0.60 + 1.40: the compiler checks the member after `shaped`, outside its entry.
        #expect(mapped.totals.milliseconds == 3)
    }

    @Test("a stored property's time goes to its type, a global's initialiser to its file; null ms for expressions only")
    func attachments() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let root = library.root
        let mapper = library.mapper
        let mapped = mapper.map([
            Self.entry(.function, 30, line: 9, column: 16, root: root),
            Self.entry(.expression, 70, line: 9, column: 25, root: root),
            Self.entry(.expression, 200, line: 15, column: 14, root: root)
        ])
        #expect(mapped.attachments == [
            BuildAttachment(owner: Self.file, attachedTo: .file, milliseconds: nil, slowestExpression: 2),
            BuildAttachment(owner: "Lib::Box", attachedTo: .type, milliseconds: 0, slowestExpression: 1)
        ])
        #expect(mapped.records.isEmpty)
        #expect(mapped.totals.milliseconds == 0)
    }

    @Test("records come sorted by key, and types and files by what they attach to, then owner, whatever the order")
    func sortedFigures() throws {
        let files = (1...4).map { index in
            (
                "Sources/Lib/Part\(index).swift",
                "struct Box\(index) {\n    var stored = 1\n}\nlet global\(index) = [1, 2].map { $0 }\n"
            )
        }
        let parts = try Library(TemporaryPackage(Dictionary(uniqueKeysWithValues: files)))
        defer { parts.package.remove() }
        let library = try Self.library()
        defer { library.package.remove() }
        let root = library.root
        let places = [(19, 14), (16, 13), (12, 9), (11, 9), (5, 10), (4, 13), (3, 13), (2, 13), (1, 13)]
        let entries = files.reversed().flatMap { file, _ in
            [(TimingEntry.Kind.function, 2, 9), (.expression, 4, 14)].map { kind, line, column in
                TimingEntry(
                    kind: kind,
                    hundredths: 100,
                    place: BuildPlace(path: parts.root + "/" + file, line: line, column: column),
                    declaration: nil
                )
            }
        }

        let timed = places.map { Self.entry(.function, 100, line: $0.0, column: $0.1, root: root) }
        let records = library.mapper.map(timed).records
        let attachments = parts.mapper.map(entries).attachments

        #expect(records.count == places.count)
        #expect(records.map(\.key) == records.map(\.key).sorted())
        #expect(attachments.map(\.owner) == files.map(\.0) + (1...4).map { "Lib::Box\($0)" })
        #expect(attachments.map(\.attachedTo) == Array(repeating: .file, count: 4) + Array(repeating: .type, count: 4))
    }

    @Test("entries left out are counted by class with their time, function and expression entries alike")
    func leftOut() throws {
        let library = try Self.library()
        defer { library.package.remove() }
        let mapped = library.mapper.map([
            TimingEntry(kind: .function, hundredths: 30, place: nil, declaration: "f"),
            TimingEntry(kind: .expression, hundredths: 30, place: nil, declaration: nil),
            TimingEntry(
                kind: .expression,
                hundredths: 150,
                place: BuildPlace(path: "@__swiftmacro_3Lib4TestfMp_.swift", line: 2, column: 3),
                declaration: nil
            )
        ])
        #expect(mapped.unmapped == BuildUnmapped(
            synthesized: BuildEntryCount(entries: 2, milliseconds: 1),
            macro: BuildEntryCount(entries: 1, milliseconds: 2)
        ))
        #expect(mapped.totals == BuildTotals(functionEntries: 1, expressionEntries: 2, milliseconds: 0))
    }
}
