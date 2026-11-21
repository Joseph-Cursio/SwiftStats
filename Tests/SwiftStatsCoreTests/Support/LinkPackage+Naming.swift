//
//  LinkPackage+Naming.swift
//  SwiftStatsCoreTests
//
//  The link package's naming cases (M5): members declared with backticks,
//  an initialiser called through an implicit `.init(…)`, a type named only
//  in a parameterized test's declaration, and witnesses through a refining
//  protocol or a superclass.
//

extension LinkPackage {
    /// The naming cases' files, a library file and a test file whose name
    /// matches none of the library's files or types.
    static let namingSources = [
        "Sources/Lib/Edge.swift": """
            public struct Cfg {
                public init() {}
                public func `default`() -> Int { 1 }
                public static var `default`: Cfg { Cfg() }
            }
            public struct Gauge {
                public init(scale: Int) {}
                public func read() -> Int { 1 }
            }
            public struct Meter {
                public init(level: Int) {}
            }
            public struct Wrapper: LosslessStringConvertible {
                public init?(_ text: String) {}
                public var description: String { "" }
            }
            open class Base: Sequence {
                open func makeIterator() -> IndexingIterator<[Int]> { [1].makeIterator() }
            }
            public final class Derived: Base {
                override public func makeIterator() -> IndexingIterator<[Int]> { [2].makeIterator() }
            }

            """,
        "Tests/LibTests/SundryTests.swift": """
            @Test func defaults() {
                let cfg = Cfg()
                #expect(cfg.default() == Cfg.default.default())
            }

            @Test func implicitInit() {
                let meter: Meter = .init(level: 1)
                _ = meter
            }

            @Test(arguments: [Gauge(scale: 1)])
            func reads(gauge: Gauge) {
                #expect(gauge.read() == 1)
            }

            """
    ]

    /// The entries of `namingSources`' library functions.
    static let namingEntries: [Entry] = [
        Entry(file: "Edge", marker: "func `default`", name: "defaultFunction"),
        Entry(file: "Edge", marker: "var `default`", name: "defaultProperty"),
        Entry(file: "Edge", marker: "init(scale", name: "gaugeInit"),
        Entry(file: "Edge", marker: "func read", name: "read"),
        Entry(file: "Edge", marker: "init(level", name: "meterInit"),
        Entry(file: "Edge", marker: "var description", name: "description"),
        Entry(file: "Edge", marker: "open func makeIterator", name: "baseIterator"),
        Entry(file: "Edge", marker: "override public func makeIterator", name: "derivedIterator")
    ]
}
