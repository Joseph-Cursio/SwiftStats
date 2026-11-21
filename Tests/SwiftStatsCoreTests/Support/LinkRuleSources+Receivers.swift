//
//  LinkRuleSources+Receivers.swift
//  SwiftStatsCoreTests
//
//  The link rules' packages for what helper calls are written on and for
//  module names (M5, tests per public function).
//

extension LinkRuleSources {
    /// Helpers called on `Self`, on a type of the target, on a typealias of
    /// one and on a type outside the target; free helpers no qualified call
    /// reaches; a test-target extension of a production type, delegating
    /// to its initialiser and calling its members bare; and a static
    /// helper of an enclosing type called bare from a nested one.
    static let receivers = [
        "Sources/Lib/Detectors.swift": """
            public enum AlphaDetector {
                public static func detect(in text: String) -> Int { 1 }
            }
            public enum BetaDetector {
                public static func detect(in text: String) -> Int { 2 }
            }
            public struct Gamma {
                public init() {}
                public func scan(_ text: String) -> Int { 3 }
            }
            public struct Point {
                public init(x: Int, y: Int) {}
                public var area: Int { 0 }
                public func grow(by step: Int) -> Int { step }
            }
            public enum Shared {
                public static func run() -> Int { 0 }
            }

            """,
        "Tests/LibTests/ReceiverTests.swift": """
            import Testing

            struct AlphaTests {
                static func detect(in text: String) -> Int { AlphaDetector.detect(in: text) }
                @Test func alpha() { #expect(Self.detect(in: "a") == 1) }
            }
            struct BetaTests {
                static func detect(in text: String) -> Int { BetaDetector.detect(in: text) }
                @Test func beta() { #expect(Self.detect(in: "b") == 2) }
            }
            func detect(in text: String) -> Int { Gamma().scan(text) }
            struct Recorder {
                static func record(_ text: String) -> Int { Gamma().scan(text) }
            }
            typealias Rec = Recorder

            @Test func recordsNothing() { Issue.record("nothing") }
            @Test func recordsGamma() { _ = Recorder.record("x") }
            @Test func recordsAlias() { _ = Rec.record("y") }

            extension Point {
                init(origin: Void) { self.init(x: 0, y: 0) }
                func doubled() -> Int { grow(by: 1) * 2 + area }
            }
            @Test func origins() { _ = Point(origin: ()) }
            @Test func doubles() { #expect(Point(x: 1, y: 1).doubled() == 2) }

            enum Fixtures {
                static func run() -> Int { Shared.run() }
                struct Inner {
                    @Test func nested() { #expect(run() == 0) }
                }
            }

            """
    ]

    /// A library and a test target whose names aren't identifiers, so
    /// their modules are written by their C99 names.
    static let moduleNames = [
        "Sources/my-lib/Tools.swift": """
            public func compute() -> Int { 1 }
            public var limit: Int { 0 }
            public struct Gauge {
                public init() {}
                public func read() -> Int { 0 }
            }

            """,
        "Tests/my-lib-tests/ToolTests.swift": """
            import Testing

            @Test func qualifiedCall() { #expect(my_lib.compute() == 1) }
            @Test func qualifiedVariable() { #expect(my_lib.limit == 0) }
            @Test func qualifiedType() { #expect(my_lib.Gauge().read() == 0) }

            """
    ]
}
