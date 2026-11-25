import Foundation
@testable import SwiftStatsCore
import Testing

/// Requirements without a body and a shorthand subscript's own accessors
/// on the Index fixture's recorded index (M7, design §3.3, §3.5, as built
/// after review C6/C33 and C8): a property or subscript requirement's
/// getters and setters, whose relations name the property, not the
/// protocol, are requirements, not outside every record; a local computed
/// property or a local type's in a shorthand subscript's body leaves the
/// subscript its getter as its secondary accessor USR.
/// Serialized, and each scan runs on a thread of its own: a test holding a
/// pool thread for seconds starves `BlockingAsyncTests`' detached tasks.
@Suite("USR join: requirements and a subscript's own accessors", .serialized)
struct USRRequirementTests {
    /// The requirements of `Protocols.swift`'s `Labeled`, a protocol of
    /// property and subscript requirements without bodies: each getter and
    /// setter (an instance one, a static one, a subscript's), whose
    /// relations name its property or subscript, not the protocol, and the
    /// subscript itself.
    static let labeledRequirements = [
        requirement("s:9IndexCore7LabeledP5labelSSvg", name: "getter:label", line: 54, column: 25),
        requirement("s:9IndexCore7LabeledP4rankSivg", name: "getter:rank", line: 56, column: 21),
        requirement("s:9IndexCore7LabeledP4rankSivs", name: "setter:rank", line: 56, column: 25),
        requirement(
            "s:9IndexCore7LabeledP8fallbackxvgZ",
            name: "getter:fallback",
            line: 58,
            column: 33,
            kind: IndexSymbolKind.staticMethod
        ),
        requirement(
            "s:9IndexCore7LabeledPySSSicip",
            name: "subscript(_:)",
            line: 60,
            column: 5,
            kind: IndexSymbolKind.instanceProperty
        ),
        requirement("s:9IndexCore7LabeledPySSSicig", name: "getter:subscript(_:)", line: 60, column: 38),
        requirement("s:9IndexCore7LabeledPySSSicis", name: "setter:subscript(_:)", line: 60, column: 42)
    ]

    /// The listing of a requirement of `Protocols.swift` without a body:
    /// `name` with `usr` at `line` and `column`, a symbol of `kind` (an
    /// instance method unless given).
    private static func requirement(
        _ usr: String,
        name: String,
        line: Int,
        column: Int,
        kind: Int = IndexSymbolKind.instanceMethod
    ) -> USRListing {
        USRListing(
            kind: .noRecord,
            subreason: .requirement,
            usr: usr,
            key: nil,
            symbolKind: kind,
            name: name,
            file: "Sources/IndexCore/Protocols.swift",
            line: line,
            column: column
        )
    }

    @Test("""
        a property or subscript requirement's getters and setters, a static one included, are listed as \
        requirements, not outside every record, though their relations name the property, not the protocol
        """)
    func propertyRequirements() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let labeled = index.withoutRecord.filter { $0.usr?.hasPrefix("s:9IndexCore7LabeledP") == true }
            #expect(labeled == Self.labeledRequirements)
            #expect(index.withoutRecord.contains { $0.subreason == .outsideRecords } == false)
        }
    }

    @Test("""
        a shorthand subscript whose body declares a local computed property and a local type with one keeps \
        its getter as its secondary accessor USR: the nested getters are not its accessors
        """)
    func subscriptWithNestedAccessors() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let records = Dictionary(uniqueKeysWithValues: index.records.map { ($0.key, $0) })
            let key = "IndexCore::Storage::subscript(doubled: Int) -> Int"
            let doubled = try #require(records[key])
            #expect(doubled.usr == "s:9IndexCore7StorageV7doubledS2i_tcip")
            #expect(doubled.usrAccessor == "s:9IndexCore7StorageV7doubledS2i_tcig")
            #expect(records[key + " / var twice: Int { get }"]?.usr
                == "s:9IndexCore7StorageV7doubledS2i_tcig5twiceL_Sivg")
            #expect(records[key + " / Offset::var amount: Int { get }"]?.usr
                == "s:9IndexCore7StorageV7doubledS2i_tcig6OffsetL_V6amountSivg")
            #expect(index.withoutRecord.contains { $0.subreason == .incompatibleKind } == false)
        }
    }

    @Test("""
        only a subscript's explicit accessors, named subscript, give it accessor records of its own; an \
        accessor record of a nested property under it doesn't
        """)
    func ownAccessors() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let records = fixture.measured.records
        let owners = USRJoin.subscriptsWithAccessors(records)
        #expect(owners.contains("IndexCore::Storage::subscript(slot: Int) -> Int"))
        #expect(owners.contains("IndexCore::Storage::subscript(doubled: Int) -> Int") == false)
        let nested = records.filter { $0.parentKey == "IndexCore::Storage::subscript(doubled: Int) -> Int" }
        #expect(nested.map(\.key).sorted() == [
            "IndexCore::Storage::subscript(doubled: Int) -> Int / Offset::var amount: Int { get }",
            "IndexCore::Storage::subscript(doubled: Int) -> Int / var twice: Int { get }"
        ])
        #expect(nested.allSatisfy { $0.kind == .accessor })
    }
}
