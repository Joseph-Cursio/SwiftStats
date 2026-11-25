//
//  IndexSymbolKindTests.swift
//  SwiftStatsCoreTests
//
//  The raw symbol constants SwiftStats reads (M7, design §2.2), pinned to
//  indexstore-db 64aa0b2's numbers, and the `init` accessor's raw subkind
//  1016 as the recording holds it.
//

@testable import SwiftStatsCore
import Testing

/// The index store's raw symbol constants.
@Suite("Index symbol constants")
struct IndexSymbolKindTests {
    @Test("the symbol kinds have indexstore-db's raw values")
    func kinds() {
        let kinds = [
            IndexSymbolKind.enum, IndexSymbolKind.struct, IndexSymbolKind.class, IndexSymbolKind.protocol,
            IndexSymbolKind.extension, IndexSymbolKind.typealias, IndexSymbolKind.function,
            IndexSymbolKind.variable, IndexSymbolKind.enumConstant, IndexSymbolKind.instanceMethod,
            IndexSymbolKind.classMethod, IndexSymbolKind.staticMethod, IndexSymbolKind.instanceProperty,
            IndexSymbolKind.classProperty, IndexSymbolKind.staticProperty, IndexSymbolKind.constructor,
            IndexSymbolKind.destructor, IndexSymbolKind.parameter
        ]

        #expect(kinds == [5, 6, 7, 8, 9, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22, 23, 25])
    }

    @Test("the subkinds have indexstore-db's raw values, and the init accessor is 1016")
    func subkinds() {
        typealias Subkind = IndexSymbolKind.Subkind
        let subkinds = [
            Subkind.plain, Subkind.accessorGetter, Subkind.accessorSetter, Subkind.swiftAccessorWillSet,
            Subkind.swiftAccessorDidSet, Subkind.swiftAccessorAddressor, Subkind.swiftAccessorMutableAddressor,
            Subkind.swiftPrefixOperator, Subkind.swiftPostfixOperator, Subkind.swiftInfixOperator,
            Subkind.swiftSubscript, Subkind.swiftAccessorRead, Subkind.swiftAccessorModify, Subkind.swiftAccessorInit
        ]

        #expect(subkinds == [0, 3, 4, 1_000, 1_001, 1_002, 1_003, 1_008, 1_009, 1_010, 1_011, 1_014, 1_015, 1_016])
    }

    @Test("the properties and roles have indexstore-db's bits")
    func bits() {
        typealias Role = IndexSymbolKind.Role
        typealias Relation = IndexSymbolKind.RelationRole
        let roles = [
            Role.declaration, Role.definition, Role.reference, Role.read, Role.write, Role.call, Role.dynamic,
            Role.implicit
        ]
        let relations = [
            Relation.childOf, Relation.baseOf, Relation.overrideOf, Relation.receivedBy, Relation.calledBy,
            Relation.extendedBy, Relation.accessorOf, Relation.containedBy
        ]

        #expect(IndexSymbolKind.Property.unitTest == 8)
        #expect(IndexSymbolKind.Property.local == 128)
        #expect(roles == [1, 2, 4, 8, 16, 32, 64, 256])
        #expect(relations == [512, 1_024, 2_048, 4_096, 8_192, 16_384, 32_768, 65_536])
    }

    @Test("the recording defines the init accessor of a stored property as an instance method of subkind 1016")
    func initAccessor() throws {
        let source = try RecordedIndexSource(recording: IndexFixture.data("reader.json"), restoring: [:])
        let record = try source.record(named: "Accessors.swift-8ROXMIAYDKZA")
        let accessors = record.occurrences.filter { $0.subkind == IndexSymbolKind.Subkind.swiftAccessorInit }
        let definition = try #require(accessors.first { $0.roles & IndexSymbolKind.Role.definition != 0 })

        #expect(definition.name == "init:value")
        #expect(definition.kind == IndexSymbolKind.instanceMethod)
        #expect(definition.line == 99)
        #expect(definition.column == 9)
    }
}
