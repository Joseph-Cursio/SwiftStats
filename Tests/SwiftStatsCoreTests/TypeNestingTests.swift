import SwiftParser
@testable import SwiftStatsCore
import Testing

/// Which package types are nested in which (M7, design §4.3), so that
/// their references to each other make no USR type-cycle edge: from source
/// text and hand-made type definitions, no fixture or index store.
@Suite("Type nesting")
struct TypeNestingTests {
    /// A type with a `private` nested class, a type declared in a
    /// `private extension`, a file-scoped type with a nested one, and a
    /// type whose name merely starts with another's.
    private static let source = """
        struct Outer {
            func make() -> Int { 1 }
            private final class Visitor {
                let outer = Outer()
            }
        }
        private extension Outer {
            struct Helper {}
        }
        private struct Hidden {
            struct Inside {}
        }
        struct OuterBand {}
        """

    /// Each type of `source`'s definition: its USR, index kind and name.
    private static let definitions = [
        definition("s:3Lib5OuterV", IndexSymbolKind.struct, at: SourcePosition(line: 1, column: 8)),
        definition("s:3Lib5OuterV7Visitor", IndexSymbolKind.class, at: SourcePosition(line: 3, column: 25)),
        definition("s:3Lib5OuterV6Helper", IndexSymbolKind.struct, at: SourcePosition(line: 8, column: 12)),
        definition("s:3Lib6HiddenV", IndexSymbolKind.struct, at: SourcePosition(line: 10, column: 16)),
        definition("s:3Lib6HiddenV6Inside", IndexSymbolKind.struct, at: SourcePosition(line: 11, column: 12)),
        definition("s:3Lib9OuterBandV", IndexSymbolKind.struct, at: SourcePosition(line: 13, column: 8))
    ]

    /// An explicit definition of the type `usr`, of index kind `kind`,
    /// named at `position`.
    private static func definition(_ usr: String, _ kind: Int, at position: SourcePosition) -> IndexOccurrenceFact {
        IndexOccurrenceFact(
            line: position.line,
            column: position.column,
            roles: IndexSymbolKind.Role.definition,
            usr: usr,
            name: usr,
            kind: kind,
            subkind: IndexSymbolKind.Subkind.plain,
            properties: 0,
            relations: []
        )
    }

    /// The ownership `source`'s type records and `definitions` give, in
    /// a production target.
    private static func ownership() throws -> TypeOwnership {
        let records = CollectorHarness.types(source)
        let file = try #require(records.first?.file)
        let facts = OccurrenceFacts(occurrences: [file: definitions], targets: [file: "Lib"], joinable: [file])
        return TypeOwnership(
            facts: facts,
            records: records,
            fileScopedTypes: [file: FileScopedTypes.paths(in: Parser.parse(source: source))],
            testModules: [],
            joinable: [file]
        )
    }

    @Test("""
        a private type nested in a plain one, or declared in a private extension of it, is nested in it though \
        only the inner type is file-scoped
        """)
    func privateNestedType() throws {
        let ownership = try Self.ownership()
        #expect(ownership.types.count == Self.definitions.count && ownership.unplaced == 0)
        let outer = try #require(ownership.types["s:3Lib5OuterV"]?.identity)
        let visitor = try #require(ownership.types["s:3Lib5OuterV7Visitor"]?.identity)
        #expect(outer.typeFile.isEmpty && visitor.typePath == "Outer.Visitor" && visitor.typeFile.isEmpty == false)
        #expect(ownership.isNested("s:3Lib5OuterV", "s:3Lib5OuterV7Visitor"))
        #expect(ownership.isNested("s:3Lib5OuterV7Visitor", "s:3Lib5OuterV"))
        #expect(ownership.isNested("s:3Lib5OuterV", "s:3Lib5OuterV6Helper"))
        #expect(ownership.isNested("s:3Lib6HiddenV6Inside", "s:3Lib6HiddenV"))
    }

    @Test("siblings, unrelated types and a type whose name only starts with another's aren't nested")
    func unrelatedTypes() throws {
        let ownership = try Self.ownership()
        #expect(ownership.isNested("s:3Lib5OuterV", "s:3Lib9OuterBandV") == false)
        #expect(ownership.isNested("s:3Lib5OuterV7Visitor", "s:3Lib5OuterV6Helper") == false)
        #expect(ownership.isNested("s:3Lib5OuterV", "s:3Lib6HiddenV") == false)
        #expect(ownership.isNested("s:3Lib5OuterV", "s:3Lib5Other") == false)
    }

    @Test("""
        a type isn't nested in a type of its path in another target, in a file-scoped type of another file, or \
        in itself
        """)
    func identities() {
        let inner = TypeIdentity(module: "Lib", typePath: "Outer.Visitor", typeFile: "Sources/Lib/A.swift")
        #expect(inner.isNested(in: TypeIdentity(module: "Lib", typePath: "Outer", typeFile: "")))
        #expect(inner.isNested(in: TypeIdentity(module: "Lib", typePath: "Outer", typeFile: "Sources/Lib/A.swift")))
        #expect(inner.isNested(in: TypeIdentity(module: "App", typePath: "Outer", typeFile: "")) == false)
        let elsewhere = TypeIdentity(module: "Lib", typePath: "Outer", typeFile: "Sources/Lib/B.swift")
        #expect(inner.isNested(in: elsewhere) == false)
        #expect(inner.isNested(in: inner) == false)
    }
}
