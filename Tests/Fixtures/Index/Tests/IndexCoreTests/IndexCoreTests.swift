@testable import IndexCore
import index_kit
import index_support
import Testing

/// The Index fixture's Swift Testing tests.
struct IndexCoreTests {
    /// Calls what only tests call.
    @Test func onlyTests() {
        #expect(onlyTestsCall() == 21)
        #expect(publicOnlyTests() == 3)
        #expect(kitOnlyTests() == 6)
        #expect(parseLine("a,b") == ["a", "b"])
    }

    /// Writes the level, which production code only reads.
    @Test func writesLevel() {
        var threshold = Threshold()
        threshold.level = 5
        #expect(threshold.stored == 5)
    }

    /// A comparison with `nil` of a non-optional inside `#expect`: the
    /// compiler reports it at the argument, in this file.
    @Test func nonOptional() {
        let count = Storage().count
        #expect(count != nil)
    }

    /// A `try` before a call that doesn't throw inside `#expect`: reported in
    /// the macro's expansion, placed by its origin note.
    @Test func needlessTry() {
        #expect(try layout(1) == 9)
    }

    /// A redundant `#require` whose argument spans lines.
    @Test func redundantRequire() {
        let session = try? #require(Session(
            name: "spanning"
        ))
        #expect(session?.open() == "open spanning")
    }

    /// A parameterized test whose arguments reference production code.
    @Test(arguments: IndexCore.cases())
    func positive(value: Int) {
        #expect(value > 0)
    }
}
