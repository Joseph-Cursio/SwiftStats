@testable import SwiftStatsCore
import Testing

/// The maximal covered units behind dead lines (M7, design §5.4), on
/// hand-made units: a record below a covered record, a nested type, a
/// type's extension record and a record in a type's body are held; the
/// lines don't depend on the order the units are added in; two units
/// holding each other count once.
@Suite("Maximal dead-code units")
struct DeadCodeUnitsTests {
    /// A span of `first` to `last` line, from column 1 to 1.
    private static func span(_ first: Int, _ last: Int) -> SourceSpan {
        SourceSpan(start: SourcePosition(line: first, column: 1), end: SourcePosition(line: last, column: 1))
    }

    /// The unit of record `key` in `file` over `first`...`last`, of
    /// `lines` lines in module `M`.
    private static func record(_ key: String, _ file: String, _ first: Int, _ last: Int, lines: Int) -> DeadCodeUnit {
        DeadCodeUnit(
            kind: .record(key),
            identifier: "record " + key,
            regions: [DeadCodeUnit.Region(file: file, span: span(first, last))],
            extensions: [],
            parts: [DeadCodeUnit.Part(module: "M", lines: lines)]
        )
    }

    /// The unit of type `path` over `first`...`last` of `a.swift` (`lines`
    /// lines) with `extensions`, regions and lines.
    private static func type(
        _ path: String,
        _ first: Int,
        _ last: Int,
        lines: Int,
        extensions: [(DeadCodeUnit.Region, Int)]
    ) -> DeadCodeUnit {
        let main = DeadCodeUnit.Region(file: "a.swift", span: span(first, last))
        return DeadCodeUnit(
            kind: .type(TypeIdentity(module: "M", typePath: path, typeFile: "")),
            identifier: "type " + path,
            regions: [main] + extensions.map(\.0),
            extensions: Set(extensions.map(\.0)),
            parts: [DeadCodeUnit.Part(module: "M", lines: lines)]
                + extensions.map { DeadCodeUnit.Part(module: "M", lines: $0.1) }
        )
    }

    /// The unit of the extension record over `first`...`last` of `file`.
    private static func extensionRecord(_ file: String, _ first: Int, _ last: Int, lines: Int) -> DeadCodeUnit {
        DeadCodeUnit(
            kind: .extensionRecord,
            identifier: "extension \(file) \(first)",
            regions: [DeadCodeUnit.Region(file: file, span: span(first, last))],
            extensions: [],
            parts: [DeadCodeUnit.Part(module: "M", lines: lines)]
        )
    }

    /// The lines of `units` added in order, records' parents `parents`.
    private static func lines(_ units: [DeadCodeUnit], parents: [String: String]) -> [String: Int] {
        var all = DeadCodeUnits(parents: parents)
        for unit in units {
            all.add(unit)
        }
        return all.lines()
    }

    @Test("""
        a record below a covered record, a nested type, the type's extension record in another file and the \
        records in its body and extension are held by what covers them, in any order
        """)
    func heldUnits() {
        let extensionRegion = DeadCodeUnit.Region(file: "b.swift", span: Self.span(1, 6))
        let units = [
            Self.type("Outer", 1, 20, lines: 8, extensions: [(extensionRegion, 5)]),
            Self.type("Outer.Inner", 4, 10, lines: 4, extensions: []),
            Self.extensionRecord("b.swift", 1, 6, lines: 5),
            Self.record("method", "a.swift", 12, 14, lines: 3),
            Self.record("extra", "b.swift", 2, 4, lines: 3),
            Self.record("free", "c.swift", 1, 9, lines: 7),
            Self.record("local", "c.swift", 3, 5, lines: 3)
        ]
        let parents = ["local": "free", "method": "Outer"]
        #expect(Self.lines(units, parents: parents) == ["M": 20])
        #expect(Self.lines(units.reversed(), parents: parents) == ["M": 20])
        var all = DeadCodeUnits(parents: parents)
        for unit in units {
            all.add(unit)
        }
        #expect(all.maximal().map(\.identifier) == ["record free", "type Outer"])
    }

    @Test("""
        a local record lying in another record's range but not below it by parentKey isn't held by that \
        record, and an empty unit adds no module
        """)
    func recordsByParentOnly() {
        let units = [
            Self.record("first", "a.swift", 1, 9, lines: 7),
            Self.record("second", "a.swift", 3, 5, lines: 3),
            Self.record("empty", "z.swift", 1, 1, lines: 0)
        ]
        #expect(Self.lines(units, parents: [:]) == ["M": 10])
        #expect(Self.lines(units, parents: ["second": "first"]) == ["M": 7])
    }

    @Test("two units holding each other count once: the first by identifier")
    func mutualHoldCountsOnce() {
        let region = DeadCodeUnit.Region(file: "a.swift", span: Self.span(1, 30))
        let units = [
            Self.type("Wrapped", 2, 10, lines: 8, extensions: [(region, 0)]),
            Self.extensionRecord("a.swift", 1, 30, lines: 25)
        ]
        var all = DeadCodeUnits(parents: [:])
        for unit in units {
            all.add(unit)
        }
        #expect(all.maximal().map(\.identifier) == ["extension a.swift 1"])
        #expect(all.lines() == ["M": 25])
    }
}
