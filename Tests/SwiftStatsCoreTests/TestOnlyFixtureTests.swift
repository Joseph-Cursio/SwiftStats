import Foundation
@testable import SwiftStatsCore
import Testing

/// Test-only production code (M7, design §8.3, §13 step 9a) on the Index
/// fixture, scanned with its recorded build and index, stored and read
/// back: `onlyTestsCall()`, `index-support`'s `parseLine(_:)` (public, but
/// in no library product) and the setter only a test writes are listed;
/// public API of `IndexCore` and `index-kit` (a dashed library-product
/// target, by target name), the witness and the default implementation,
/// `Tool.main()` and `Session`'s deinitializer are counted out; a nested
/// function its parent calls has no reference, since references within a
/// family don't count. Serialized: the fixture scan runs on a thread of
/// its own, as the index collector's tests do.
@Suite("Test-only production code on the Index fixture", .serialized)
struct TestOnlyFixtureTests {
    /// The funnel the fixture gives, as the checker counts it on a real
    /// scan of the fixture.
    private static let funnel = "93 production functions = 3 without a USR (2 inactive #if branch, 1 top-level "
        + "code) + 90 with one; 90 = 57 public API of a library product + 2 witnesses or overrides + 0 @objc + 1 "
        + "entry points + 1 deinitializers + 29 "
        + "candidates; 29 = 3 listed + 15 with a production reference + 11 with no reference at all (not listed: "
        + "fan-in 0 isn't dead, PRD §7.6a)"

    /// Checks the signal and the verdicts on `snapshot`, the fixture's
    /// stored scan.
    private static func expectSignal(_ snapshot: StoredSnapshot) throws {
        let signal = try TestOnlyHarness.signal(snapshot)
        let verdicts = try TestOnlyHarness.verdicts(snapshot)

        #expect(snapshot.executableTargets == ["IndexApp", "IndexTool"])
        #expect(signal.leftOut == nil)
        #expect(signal.rule == TestOnlyProduction.rule + "; " + funnel)
        #expect(signal.items.map(\.subject) == [
            "IndexCore::Threshold::var level: Int { set }",
            "IndexCore::func onlyTestsCall() -> Int",
            "index-support::func parseLine(_: String) -> [String]"
        ])
        #expect(signal.items.map(\.score) == [1, 1, 1])
        #expect(signal.items.map { "\($0.file):\($0.line)" } == [
            "Sources/IndexCore/References.swift:37",
            "Sources/IndexCore/TestOnly.swift:7",
            "Sources/Kits/Support.swift:5"
        ])
        #expect(signal.items.compactMap(\.references) == [
            SignalItem.References(
                tests: 1,
                testReferrers: ["IndexCoreTests::IndexCoreTests::func writesLevel()"],
                module: "IndexCore"
            ),
            SignalItem.References(
                tests: 1,
                testReferrers: ["IndexCoreTests::IndexCoreTests::func onlyTests()"],
                module: "IndexCore"
            ),
            SignalItem.References(
                tests: 1,
                testReferrers: ["IndexCoreTests::IndexCoreTests::func onlyTests()"],
                module: "index-support"
            )
        ])
        #expect(verdicts["IndexCore::Threshold::var level: Int { get }"] == .production)
        #expect(verdicts["IndexCore::func layout(_: Int) -> Int / func padded(_: Int) -> Int"] == .unreferenced)
        #expect(verdicts["IndexCore::func publicOnlyTests() -> Int"] == .excluded(.publicAPI))
        #expect(verdicts["index-kit::func kitOnlyTests() -> Int"] == .excluded(.publicAPI))
        #expect(verdicts["IndexCore::Tile::func area() -> Int"] == .excluded(.witness))
        #expect(verdicts["IndexCore::Greeter::func greet() -> String"] == .excluded(.witness))
        #expect(verdicts["IndexTool::Tool::static func main()"] == .excluded(.entryPoint))
        #expect(verdicts["IndexCore::Session::deinit"] == .excluded(.deinitializer))
        #expect(verdicts["IndexApp::<top-level code> @ Sources/IndexApp/main.swift"] == .withoutUSR(.topLevelCode))
        #expect(verdicts.values.filter { $0 == .withoutUSR(.inactiveIfBranch) }.count == 2)
    }

    @Test("""
        the fixture lists the setter only a test writes, onlyTestsCall() and index-support's parseLine(_:), and \
        counts the rest out in the design's order, its funnel's parts summing
        """)
    func fixture() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        try await scan.run { _, outcome in
            let made = try TemporaryStore("TestOnlyFixture")
            defer { made.remove() }

            let snapshot = try made.store.load(id: try made.store.save(outcome.snapshot))

            try Self.expectSignal(snapshot)
            let plain = try made.store.load(id: try made.store.save(IndexStoreSamples.plain(outcome.snapshot)))
            #expect(plain.executableTargets.isEmpty)
            #expect(try TestOnlyHarness.signal(plain).leftOut == "needs index: skipped, "
                + BuildAdapter.notRequestedReason)
        }
    }
}
