//
//  LinkRuleSources.swift
//  SwiftStatsCoreTests
//
//  Small packages for the link rules' tests (M5, tests per public
//  function), one per part of the rule. Each has a library `Lib` and a
//  test target `LibTests`, whose test files are named for none of the
//  library's files or types, so no test counts by its file's name.
//

/// The link rules' packages.
enum LinkRuleSources {
    /// Overloads of protocol extension members and free functions told apart
    /// by labels, defaults, trailing closures, variadic and unlabelled
    /// parameters; tuple labels, locals and local functions named like
    /// members, and a free function's name called on a value.
    static let overloads = [
        "Sources/Lib/Seq.swift": """
            extension Sequence {
                public func splitUp(separator: Int, maxSplits: Int = 0) -> Int { 0 }
                public func splitUp(maxSplits: Int = 0, whereSeparator: (Element) -> Bool) -> Int { 0 }
                public func least(count: Int) -> Int { 0 }
                public func least(count: Int, sortedBy: (Element, Element) -> Bool) -> Int { 0 }
                public var firstOrZero: Int { 0 }
            }
            public func total(_ values: Int...) -> Int { 0 }
            public func total(of values: [Int]) -> Int { 0 }
            public func label(_ value: Int) -> String { "" }
            public func label(value: Int) -> String { "" }

            """,
        "Tests/LibTests/OverloadTests.swift": """
            @Test func separators() { #expect([1].splitUp(separator: 1) == 0) }
            @Test func closures() { #expect([1].splitUp { $0 == 0 } == 0) }
            @Test func closuresWithMax() { #expect([1].splitUp(maxSplits: 1) { $0 == 0 } == 0) }
            @Test func leastCount() { #expect([1].least(count: 1) == 0) }
            @Test func leastSorted() { #expect([1].least(count: 1) { $0 < $1 } == 0) }
            @Test func leastReference() { let pick = [1].least(count:sortedBy:); _ = pick }
            @Test func leastTuple() { let pair = (least: 1, most: 2); #expect(pair.least == 1) }
            @Test func leastLocal() { let least = 3; #expect(least == 3) }
            @Test func totals() { #expect(total() + total(1, 2) == 0) }
            @Test func totalsOf() { #expect(total(of: [1]) == 0) }
            @Test func labels() { #expect(label(1).isEmpty) }
            @Test func labelsNamed() { #expect(Lib.label(value: 1).isEmpty) }
            @Test func firstValue() { #expect([1].firstOrZero == 0) }
            @Test func firstLocal() { let firstOrZero = 2; #expect(firstOrZero == 2) }
            @Test func leastLocalFunction() { func least(count: Int) -> Int { count }; #expect(least(count: 1) == 1) }
            @Test func totalsOnValue() { #expect(box.total(of: [1]) == 0) }

            """
    ]

    /// A concrete type's initialisers called in every form, its accessors
    /// read as members, by key paths, by calling the closure one holds or
    /// not at all, a member function named like a local, nested types
    /// sharing a simple name, and a free variable read bare and qualified.
    static let members = [
        "Sources/Lib/Shapes.swift": """
            public struct Shelf {
                public init(size: Int) {}
                public init(width: Int, height: Int = 1) {}
                public var area: Int { 0 }
                public static var standard: Shelf { Shelf(size: 1) }
                public func root(forScanOf path: String) -> String { path }
                public var maker: () -> Int { { 0 } }
            }
            public enum Harvester {
                public struct Corpus {
                    public init() {}
                }
            }
            public enum Command {
                public struct Corpus {
                    public init() {}
                    public func run() -> Int { 0 }
                }
            }
            public var counter: Int { 0 }

            """,
        "Tests/LibTests/StorageTests.swift": """
            @Test func sizes() { let shelf = Shelf(size: 1); _ = shelf }
            @Test func widths() { let shelf = Shelf.init(width: 2); _ = shelf }
            @Test func implicit() { let shelf: Shelf = .init(width: 1, height: 2); _ = shelf }
            @Test func qualified() { _ = Lib.Shelf(size: 2) }
            @Test func areas() { #expect(Shelf.standard.area == 0) }
            @Test func bareArea() { let area = 3; let shelf = Shelf(size: 1); _ = shelf; #expect(area == 3) }
            @Test func keyPaths() { #expect([Shelf(size: 1)].map(\\Shelf.area) == [0]) }
            @Test func roots() {
                let root = "x"
                let shelf = Shelf(size: 1)
                #expect(shelf.root(forScanOf: root) == root)
            }
            @Test func localRoot() { let root = Shelf(size: 1); _ = root }
            @Test func harvested() { _ = Harvester.Corpus() }
            @Test func commanded() { _ = Command.Corpus().run() }
            @Test func harvestedRun() { _ = Harvester.Corpus(); _ = thing.run() }
            @Test func unqualifiedCorpus() { let corpus: Corpus? = nil; _ = corpus?.run() }
            @Test func counters() { #expect(counter == 0) }
            @Test func qualifiedCounter() { #expect(Lib.counter == 0) }
            @Test func makers() { _ = Shelf(size: 1).maker() }

            """
    ]

    /// Test helpers reached transitively, through a cycle, and one whose
    /// labels no call fits; an initialiser helper no call fits and one
    /// called with a qualifier that isn't its type's; a `private` helper of
    /// another file named like a visible one, member helpers called bare
    /// from their own type, another type and a subclass; a function nested
    /// in a test, and a helper of another test target named like one of
    /// this target's.
    static let helpers = [
        "Sources/Lib/Engine.swift": """
            public struct Engine {
                public func start() -> Int { 1 }
                public func stop() -> Int { 0 }
                public func idle() -> Int { 2 }
            }

            """,
        "Tests/LibTests/RigTests.swift": """
            func startEngine() -> Int { warmUp(Engine()) }
            func warmUp(_ engine: Engine) -> Int { engine.start() + ping(1) }
            func ping(_ count: Int) -> Int { count > 0 ? pong(count - 1) : 0 }
            func pong(_ count: Int) -> Int { ping(count) + Engine().stop() }
            func pong(label: String) -> Int { Engine().idle() }
            struct Rig {
                init(engine: Engine) { _ = engine.idle() }
                init(label: String) { _ = Engine().start() }
            }

            @Test func starts() { #expect(startEngine() == 1) }
            @Test func pings() { #expect(ping(2) == 0) }
            @Test func rigs() { _ = Rig(engine: Engine()) }
            @Test func otherRigs() { _ = Other.Rig(engine: Engine()) }
            @Test func hosts() { func tuneUp() -> Int { Engine().idle() }; #expect(tuneUp() == 2) }
            @Test func borrows() { #expect(tuneUp() == 2) }

            """,
        "Tests/LibTests/BenchTests.swift": """
            import XCTest

            private func startEngine() -> Int { Engine().idle() }

            struct Bench {
                func spin() -> Int { Engine().idle() }
                @Test func benches() { #expect(spin() == 2) }
            }

            struct Stand {
                @Test func stands() { #expect(spin() == 2) }
            }

            class BaseCase: XCTestCase {
                func revUp() -> Int { Engine().stop() }
            }

            final class DerivedCase: BaseCase {
                func testRevs() { XCTAssertEqual(revUp(), 0) }
            }

            """,
        "Tests/OtherTests/OtherTests.swift": """
            func warmUp(_ engine: Engine) -> Int { engine.idle() }

            """
    ]

    /// Swift Testing tests, free, in a type with no `@Suite`, nested in a
    /// tagged `@Suite` after another attribute, and in a type an extension
    /// of that suite declares, and XCTest tests, all calling one function,
    /// for `--skip` regexes.
    static let skips = [
        "Sources/Lib/Compute.swift": """
            public func compute() -> Int { 1 }

            """,
        "Tests/LibTests/SkipTests.swift": """
            import Testing
            import XCTest

            @Test func fastCompute() { #expect(compute() == 1) }

            struct MeasuredSuite {
                @Test func slowCompute(_ unused: Int) { #expect(compute() == 1) }
            }

            final class ComputeXCTests: XCTestCase {
                func testCompute() { XCTAssertEqual(compute(), 1) }
                func testMeasuredCompute() { XCTAssertEqual(compute(), 1) }
            }

            @Suite(.tags(.slow)) struct TaggedSuite {
                struct Deep {
                    @MainActor @Test func deepCompute() { #expect(compute() == 1) }
                }
            }

            extension TaggedSuite {
                struct Far {
                    @Test func farCompute() { #expect(compute() == 1) }
                }
            }

            """
    ]
}
