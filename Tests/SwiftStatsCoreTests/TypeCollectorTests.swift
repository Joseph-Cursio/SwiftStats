@testable import SwiftStatsCore
import Testing

/// Type records (PRD §7.2): names, nesting, local types, `#if` and member counts.
@Suite("Type collector")
struct TypeCollectorTests {
    @Test("nested types take the enclosing path; local types start a fresh one")
    func paths() {
        let types = CollectorHarness.types("""
        struct Outer {
            enum Inner { case first }
            func make() {
                struct Local {}
                _ = { class InClosure {} }
            }
        }
        extension Outer.Inner {}
        """)

        #expect(types.map(\.name) == ["Outer", "Outer.Inner", "Local", "InClosure", "Outer.Inner"])
        #expect(types.map(\.kind) == [.structType, .enumType, .structType, .classType, .extensionDeclaration])
        #expect(types.map(\.isLocal) == [false, false, true, true, false])
    }

    @Test("members count bindings and case elements once each, flattening #if")
    func memberCounts() {
        let types = CollectorHarness.types("""
        enum Token {
            case word(String), number(Int)
            case end
            var a = 0, b = 1
            #if DEBUG
            func dump() {}
            #else
            typealias Alias = Int
            #endif
            struct Nested {}
            init() { self = .end }
            subscript(index: Int) -> Int { index }
            #warning("macro expansions are not members")
        }
        """)

        #expect(types.first?.memberCount == 10)
        #expect(types.last?.memberCount == 0)
    }

    @Test("types in a macro's arguments get no record, like the functions there")
    func macros() {
        let types = CollectorHarness.types("#Preview {\n    struct Demo {}\n    return Demo()\n}\nstruct Kept {}")

        #expect(types.map(\.name) == ["Kept"])
    }

    @Test("length excludes attributes and comments; #if conditions are kept")
    func lengthAndConditions() {
        let types = CollectorHarness.types("""
        @available(macOS 14, *)
        // a comment
        public struct Shown {
            // another comment
            var value = 0
        }
        #if os(macOS)
        actor OnlyMac {}
        #endif
        """)

        #expect(types.first?.strippedLines == 3)
        #expect(types.first?.range.start.line == 1)
        #expect(types.last?.ifConfig == "os(macOS)")
        #expect(types.last?.kind == .actor)
    }
}
