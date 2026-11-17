import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax
import Testing

@Suite("Function keys: stability and roles")
struct FunctionKeyStabilityTests {
    // MARK: - Stability (PRD M0 done-when 3)

    @Test("inserting lines above or reformatting leaves key and body hash unchanged")
    func stableUnderEdits() {
        let original = """
        struct Model {
            func total(of items: [Int], scale: Double) -> Double {
                items.reduce(0) { $0 + Double($1) } * scale
            }
        }
        """
        let edited = """
        import Foundation

        // A new comment block.
        struct Model {
            let added = 1

            func total(
                of values: [Int],   // renamed internal parameter
                scale factor: Double
            ) -> Double
            {
                // reformatted body with a comment
                items.reduce( 0 ) { $0 + Double( $1 ) }
                    * scale
            }
        }
        """
        let before = CollectorHarness.collect(original)[0]
        let after = CollectorHarness.collect(edited)[0]

        #expect(before.key == after.key)
        #expect(before.bodyHash == after.bodyHash)
        #expect(before.range != after.range)
    }

    @Test("moving a file keeps a non-private key and changes a private one")
    func moveFile() {
        let source = "func visible() { }\nprivate func hidden() { }\n"
        let before = CollectorHarness.keys(source, file: "Sources/Lib/Old.swift")
        let after = CollectorHarness.keys(source, file: "Sources/Lib/Sub/New.swift")

        #expect(before[0] == after[0])
        #expect(before[1] != after[1])
    }

    @Test("changing the signature changes the key; changing the body changes only the hash")
    func signatureAndBodyChanges() {
        let base = CollectorHarness.collect("func area(width: Int) -> Int { width * 2 }")[0]
        let relabelled = CollectorHarness.collect("func area(size: Int) -> Int { width * 2 }")[0]
        let retyped = CollectorHarness.collect("func area(width: Double) -> Int { width * 2 }")[0]
        let rebodied = CollectorHarness.collect("func area(width: Int) -> Int { width * 3 }")[0]

        #expect(base.key != relabelled.key)
        #expect(base.key != retyped.key)
        #expect(base.key == rebodied.key)
        #expect(base.bodyHash != rebodied.bodyHash)
    }

    // MARK: - Roles

    @Test("Swift Testing and XCTest tests are tests; other test-target code is helpers")
    func roles() {
        let source = """
        import Testing
        import XCTest
        @Test func swiftTesting() { }
        func makeFixture() -> Int { 1 }
        final class MathTests: BaseCase {
            func testAddition() { }
            func testWithArgument(_ value: Int) { }
            static func testStatic() { }
            func helper() { }
        }
        extension MathTests {
            func testFromExtension() { }
        }
        """
        let records = CollectorHarness.collect(source, isTestTarget: true, testCaseClasses: ["MathTests"])
        let roles = Dictionary(uniqueKeysWithValues: records.map { ($0.name, $0.role) })

        #expect(roles["swiftTesting"] == .test)
        #expect(roles["makeFixture"] == .helper)
        #expect(roles["testAddition"] == .test)
        #expect(roles["testWithArgument"] == .helper)
        #expect(roles["testStatic"] == .helper)
        #expect(roles["helper"] == .helper)
        #expect(roles["testFromExtension"] == .test)
    }

    @Test("XCTestCase subclasses are found through intermediate base classes")
    func testCaseIndex() {
        let trees = [
            Parser.parse(source: "class BaseCase: XCTestCase { }"),
            Parser.parse(source: "final class MathTests: BaseCase { }\nclass Unrelated: NSObject { }")
        ]
        #expect(TestCaseClassIndex.testCaseClasses(in: trees) == ["BaseCase", "MathTests"])
    }

    @Test("production targets give every record the production role")
    func productionRole() {
        let records = CollectorHarness.collect("@Test func looksLikeATest() { }\nfunc testSomething() { }")
        #expect(records.allSatisfy { $0.role == .production })
    }
}
