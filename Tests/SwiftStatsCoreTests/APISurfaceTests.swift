@testable import SwiftStatsCore
import Testing

/// Declarations by access level, documentation and `final` (PRD §7.5).
@Suite("API surface")
struct APISurfaceTests {
    @Test("effective levels: written, inherited from an extension, capped by what encloses")
    func levels() {
        let source = """
        public struct Point {
            public var x = 0, y = 0
            var label = ""
            private(set) public var tag = 0
            init() { }
        }
        public extension Point {
            func moved() -> Point { self }
        }
        private extension Point {
            func secret() { }
        }
        private struct Hidden {
            func reveal() { }
        }
        open class Base {
            open func draw() { }
        }
        """
        let declarations = CollectorHarness.declarations(source)

        #expect(declarations.map(\.access) == [
            .public, .public, .public, .internal, .public, .internal, .public, .fileprivate,
            .private, .fileprivate, .open, .open
        ])
        #expect(declarations.map(\.isImplicitlyInternal) == [
            false, false, false, true, false, true, false, false, false, false, false, false
        ])
    }

    @Test("locals, protocol requirements, enum cases and macro arguments aren't counted")
    func notCounted() {
        let source = """
        protocol Shape {
            var area: Double { get }
            func draw()
        }
        enum Kind { case circle, square }
        func make() {
            struct Local { var value = 0 }
            let closure = { var inner = 1; inner += 1 }
            closure()
        }
        #hidden { struct Generated { } }
        """
        let declarations = CollectorHarness.declarations(source)

        #expect(declarations.count == 3)
        #expect(declarations.allSatisfy { $0.access == .internal && $0.isImplicitlyInternal })
    }

    @Test("declarations inside top-level statements are locals, and a tuple binds its elements' names")
    func topLevelStatementsAndTuples() {
        let source = """
        let flag = true
        for index in 0..<3 { let copy = index; struct Local { } }
        if flag { var count = 1; count += 1 }
        do { class Box { } }
        switch flag { case true: let kept = 2; _ = kept; default: break }
        #if DEBUG
        let debug = 1
        #endif
        public let (first: low, second: high) = (1, 2)
        let (left, (_, right)) = (1, (2, 3))
        """
        let declarations = CollectorHarness.declarations(source)

        // flag, debug, low, high, left and right; nothing from the statement bodies.
        #expect(declarations.count == 6)
        #expect(declarations.filter { $0.access == .public }.count == 2)
        #expect(declarations.contains(where: \.isClass) == false)
    }

    @Test("the surface counts levels, public documentation and final classes")
    func surface() {
        let source = """
        /// A documented public type.
        public final class Store {
            /// Documented.
            public func load() { }
            public func save() { }
            final class Cache { }
        }
        class Plain { }
        """
        let surface = APISurface(CollectorHarness.declarations(source), overExposed: nil)

        #expect(surface.accessLevels == ["public": 3, "internal": 2])
        #expect(surface.implicitlyInternal == 2)
        #expect(surface.publicDeclarations == 3)
        #expect(surface.documentedPublicDeclarations == 2)
        #expect(surface.classes == 3)
        #expect(surface.finalClasses == 2)
        #expect(surface.overExposed == nil)
    }
}
