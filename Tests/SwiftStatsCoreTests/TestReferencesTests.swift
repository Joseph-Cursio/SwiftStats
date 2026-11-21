import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax
import Testing

/// What a test writes, as tests per public function read it (M5): the
/// paths of its names, the members it reads and the calls it makes.
@Suite("Test references")
struct TestReferencesTests {
    /// The references of the first function in `source`.
    private static func references(_ source: String) throws -> TestReferences {
        let tree = Parser.parse(source: source)
        let function = try #require(tree.statements.first?.item.as(FunctionDeclSyntax.self))
        return TestFacts(function).references
    }

    @Test("""
        a call keeps its labels, its unlabelled trailing closure and its labelled ones in order, and what it is \
        written on; an unapplied reference counts only with labels
        """)
    func callsAndReferences() throws {
        let references = try Self.references("""
        @Test func calls() {
            list.split(maxSplits: 1) { $0 == 0 } other: { }
            f(1, b: 2)
            Algorithms.chain(a, b)
            let pick = list.max(count:sortedBy:)
            apply(transform(_:))
            let make = Bag.init(items:)
            _ = list.map(Bag.init)
            let sorter = list.sorted
            make().reset(.zero)
        }
        """)

        #expect(references.renderedCalls == [
            "list.split(maxSplits:, {}, other:)", "f(_, b:)", "Algorithms.chain(_, _)", "ref list.max(count:sortedBy:)",
            "apply(_)", "ref transform(_:)", "ref Bag.init(items:)", "list.map(_)", "make()", "(expr).reset(_)"
        ])
        // An unlabelled `list.sorted` is a member read; `Bag.init` is
        // neither a read nor a call. A member called without labels may
        // call a closure a property holds, so it is read too; one called
        // with a label isn't.
        #expect(references.members == ["sorted", "zero", "chain", "map", "reset"])
    }

    @Test("""
        a member read is not a name written alone: a local named like a member, a tuple label and a key path's \
        components are told apart from the bare identifiers
        """)
    func membersAndBareNames() throws {
        let references = try Self.references("""
        @Test func members() {
            let root = Universe.root(forScanOf: url)
            #expect(root.path.isEmpty == false)
            #expect(result?.min == 2)
            #expect(values.map(\\Bag.total) == [] && shelves.map(\\.size.width) == [])
        }
        """)

        #expect(references.members == ["path", "isEmpty", "min", "total", "size", "width", "map"])
        #expect(references.paths.contains("root"))
        #expect(references.paths.contains("min") == false)
        #expect(references.paths.contains("total") == false)
        #expect(references.renderedCalls.contains("Universe.root(forScanOf:)"))
        #expect(references.renderedCalls.contains("root(forScanOf:)") == false)
    }

    @Test("a qualified type or chain gives each of its prefixes' paths, generic arguments dropped")
    func qualifiedPaths() throws {
        let references = try Self.references("""
        @Test func corpus() {
            let corpus: Harvester.Corpus<Int> = Harvester.Corpus<Int>(items: [])
            _ = Outer.Inner.make()
        }
        """)

        #expect(references.paths == [
            "Harvester", "Harvester.Corpus", "Int", "Outer", "Outer.Inner", "Outer.Inner.make"
        ])
        #expect(references.renderedCalls == ["Harvester.Corpus(items:)", "Outer.Inner.make()"])
    }

    @Test("""
        a call on `self`, `Self` or `super` is written on the enclosing type or instance, and `Self(…)`, \
        `Self.init(…)` and `self.init(…)` call its initialiser until a type resolves them
        """)
    func enclosingType() throws {
        let references = try Self.references("""
        func make() {
            self.reset(count: 1)
            Self.detect(in: text)
            super.prepare()
            _ = Self(size: 1)
            _ = Self.init(width: 2)
            self.init(x: 0, y: 0)
            super.init()
        }
        """)

        #expect(references.renderedCalls == [
            "self.reset(count:)", "self.detect(in:)", "self.prepare()", "Self(size:)", "Self.init(width:)",
            "Self.init(x:, y:)"
        ])
        #expect(references.resolvingSelf(as: ["Kit", "Shelf"]).renderedCalls == [
            "self.reset(count:)", "self.detect(in:)", "self.prepare()", "Kit.Shelf(size:)", "Kit.Shelf.init(width:)",
            "Kit.Shelf.init(x:, y:)"
        ])
    }
}
