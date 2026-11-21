@testable import SwiftStatsCore
import Testing

/// Each function record's effective access level (M5, PRD §7.5), by the
/// rules the API surface counts declarations with.
@Suite("Function access")
struct FunctionAccessTests {
    /// A file with a record of every access shape.
    private static let source = """
        public struct Shelf {
            public init() {}
            func plain() {}
            private func hidden() {}
            package func shared() {}
            public var size: Int { 1 }
            public private(set) var label: String {
                get { "" }
                set {}
            }
            public internal(set) subscript(index: Int) -> Int {
                get { index }
                set {}
            }
            public func outer() {
                func inner() {}
            }
            public var made: Int = {
                func make() -> Int { 1 }
                return make()
            }()
        }
        open class Base {
            open func overridable() {}
            deinit {}
        }
        struct Internal {
            public func capped() {}
        }
        private struct Hidden {
            func member() {}
            public func loud() {}
        }
        public extension Shelf {
            func fromExtension() {}
        }
        private extension Shelf {
            func fromPrivateExtension() {}
        }
        extension Shelf {
            public func explicit() {}
        }
        public func free() {}
        public func makesLocalType() {
            struct Local {
                public func member() {}
            }
        }
        print("top")
        do {
            func inTop() {}
        }

        """

    @Test("""
        a record takes what it writes or its extension's default, capped by its types; an accessor its property's or \
        subscript's level, a setter its private(set) one; what is declared in a record or an initialiser is local
        """)
    func rules() {
        let file = " @ Sources/Lib/File.swift"
        let access = Dictionary(uniqueKeysWithValues: CollectorHarness.collect(Self.source).map { ($0.key, $0.access) })

        #expect(access == [
            "Lib::Shelf::init()": .public,
            "Lib::Shelf::func plain()": .internal,
            "Lib::Shelf::func hidden()" + file: .private,
            "Lib::Shelf::func shared()": .package,
            "Lib::Shelf::var size: Int { get }": .public,
            "Lib::Shelf::var label: String { get }": .public,
            "Lib::Shelf::var label: String { set }": .private,
            "Lib::Shelf::subscript(_: Int) -> Int": .public,
            "Lib::Shelf::subscript(_: Int) -> Int / { get }": .public,
            "Lib::Shelf::subscript(_: Int) -> Int / { set }": .internal,
            "Lib::Shelf::func outer()": .public,
            "Lib::Shelf::func outer() / func inner()": .local,
            "Lib::Shelf::var made: Int = <initializer> / func make() -> Int": .local,
            "Lib::Base::func overridable()": .open,
            "Lib::Base::deinit": .internal,
            "Lib::Internal::func capped()": .internal,
            "Lib::Hidden::func member()" + file: .fileprivate,
            "Lib::Hidden::func loud()" + file: .fileprivate,
            "Lib::Shelf::func fromExtension()": .public,
            "Lib::Shelf::func fromPrivateExtension()" + file: .fileprivate,
            "Lib::Shelf::func explicit()": .public,
            "Lib::func free()": .public,
            "Lib::func makesLocalType()": .public,
            "Lib::func makesLocalType() / Local::func member()": .local,
            "Lib::<top-level code>" + file: .internal,
            "Lib::<top-level code>" + file + " / func inTop()": .local
        ])
    }

    @Test("""
        an extension's members are capped by the type it extends, as swiftc exports them: a `public` member of a \
        `private`, `fileprivate` or `internal` extension of a public type is public, one of a plain extension of \
        an internal or private type is not; the extension's modifier is only their default
        """)
    func extensionMembers() {
        let extensions = """
            public struct Shelf {}
            struct Engine { init() {} }
            private struct Hidden {}
            private extension Shelf {
                public func viaPrivate() {}
                func defaulted() {}
            }
            fileprivate extension Shelf { public func viaFileprivate() {} }
            internal extension Shelf { public func viaInternal() {} }
            extension Engine { public func start() -> Int { 1 } }
            extension Engine { public struct Part { public func turn() {} } }
            extension Engine.Part { public func spin() {} }
            extension Hidden { public func peek() {} }
            extension Array { public func external() {} }

            """
        let file = " @ Sources/Lib/File.swift"
        let access = Dictionary(uniqueKeysWithValues: CollectorHarness.collect(extensions).map { ($0.key, $0.access) })

        #expect(access == [
            "Lib::Engine::init()": .internal,
            "Lib::Shelf::func viaPrivate()" + file: .public,
            "Lib::Shelf::func defaulted()" + file: .fileprivate,
            "Lib::Shelf::func viaFileprivate()" + file: .public,
            "Lib::Shelf::func viaInternal()": .public,
            "Lib::Engine::func start() -> Int": .internal,
            "Lib::Engine.Part::func turn()": .internal,
            "Lib::Engine.Part::func spin()": .internal,
            "Lib::Hidden::func peek()" + file: .fileprivate,
            "Lib::Array::func external()": .public
        ])
    }

    @Test("""
        in a scan, an extension's members are capped by the type it extends in another file of the module, in \
        the records and the API surface alike
        """)
    func extensionMembersAcrossFiles() throws {
        let package = try TemporaryPackage([
            "Sources/Lib/Types.swift": "public struct Shelf {}\nstruct Engine {}\n",
            "Sources/Lib/Extensions.swift": """
                private extension Shelf { public func viaPrivate() {} }
                extension Engine { public func start() {} }

                """
        ])
        defer { package.remove() }
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        let measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
        let access = Dictionary(uniqueKeysWithValues: measured.records.map { ($0.key, $0.access) })

        #expect(access["Lib::Shelf::func viaPrivate() @ Sources/Lib/Extensions.swift"] == .public)
        #expect(access["Lib::Engine::func start()"] == .internal)
        // Shelf and viaPrivate are public; Engine and start internal.
        #expect(measured.declarations.map(\.access).sorted() == [.internal, .internal, .public, .public])
    }

    @Test("a record's access is the level the API surface gives its declaration", arguments: [
        "public func f() {}",
        "private func f() {}",
        "public struct S { func f() {} }",
        "public struct S { public static func f() {} }",
        "struct S { public func f() {} }",
        "private struct S { public func f() {} }",
        "public enum E { struct S { public func f() {} } }",
        "public extension S { func f() {} }",
        "private extension S { public func f() {} }",
        "public struct S {}\nprivate extension S { public func f() {} }",
        "struct S {}\nextension S { public func f() {} }",
        "private struct S {}\nextension S { public func f() {} }",
        "struct S {}\nextension S { public struct T { public func f() {} } }",
        "fileprivate extension S { func f() {} }",
        "public protocol P {}\nextension P { public func f() {} }",
        "public class C { open func f() {} }",
        "public struct S { package init() {} }",
        "public struct S { public subscript(index: Int) -> Int { index } }",
        "public struct S { var value: Int { 1 } }",
        "public struct S { public var value: Int { 1 } }"
    ])
    func agreesWithAPISurface(source: String) throws {
        let record = try #require(CollectorHarness.collect(source).last)
        let declaration = try #require(CollectorHarness.declarations(source).last)

        #expect(record.access == FunctionAccess(declaration.access))
    }
}
