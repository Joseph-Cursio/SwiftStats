@testable import SwiftStatsCore
import Testing

/// Parameter counts and doc comments on function records (PRD §7.2).
@Suite("Declaration facts")
struct DeclarationFactsTests {
    @Test("parameter counts for func, init and subscript; none for other kinds")
    func parameterCounts() {
        let records = CollectorHarness.collect("""
        final class Box {
            init(width: Int, height: Int) {}
            deinit {}
            func area() -> Int { 0 }
            subscript(row: Int, column: Int) -> Int { row }
            var label: String { "" }
        }
        """)

        #expect(records.map(\.name) == ["init", "deinit", "area", "subscript", "label"])
        #expect(records.map(\.parameterCount) == [2, nil, 0, 2, nil])
    }

    @Test("doc comments on the declaration, or on the property for its accessors")
    func documentation() {
        let records = CollectorHarness.collect("""
        struct Box {
            /// Documented.
            func documented() {}
            /** Also documented. */
            @discardableResult
            func block() -> Int { 0 }
            // A plain comment is not documentation.
            func plain() {}
            /// The label.
            var label: String {
                get { "" }
                set {}
            }
            /// The size.
            var size: Int { 0 }
        }
        """)

        #expect(records.map(\.isDocumented) == [true, true, false, true, true, true])
    }
}
