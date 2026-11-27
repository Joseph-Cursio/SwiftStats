import Foundation
import Testing

/// What property tests print about their inputs (design D4, D6): under
/// `SWIFTSTATS_PBT_TRACE=1` every input, and always each check's first
/// failing input, once, before the engine starts shrinking; each line names
/// the test and describes the input as the engine's own report does.
@Suite("Property test trace")
struct PBTTraceTests {
    @Test(
        "tracing is on only when the variable is 1",
        arguments: [
            ([:], false),
            (["SWIFTSTATS_PBT_TRACE": "1"], true),
            (["SWIFTSTATS_PBT_TRACE": "0"], false),
            (["SWIFTSTATS_PBT_TRACE": "yes"], false),
            (["SWIFTSTATS_PBT_TRACE": ""], false),
            (["SWIFTSTATS_PBT_TRACE": " 1"], false)
        ]
    )
    func tracing(environment: [String: String], isOn: Bool) {
        #expect(PBTTrace.isTracing(in: environment) == isOn)
    }

    @Test("a traced input names the test and is described as the engine describes it")
    func note() {
        let input = CorpusEntry(input: 7, pins: "B0: a sample input")

        let text = PBTTrace.noteText(input, test: Test.current)

        #expect(
            text == "PBT trace [a traced input names the test and is described as the engine describes it]: "
                + "B0: a sample input"
        )
    }

    @Test("a check prints its first failing input and no later one")
    func firstFailureOnce() {
        let latch = FirstFailureLatch()

        let first = PBTTrace.firstFailureText("x\ny", test: Test.current, latch: latch)
        let second = PBTTrace.firstFailureText("z", test: Test.current, latch: latch)

        #expect(
            first == "PBT first failing input, before shrinking "
                + "[a check prints its first failing input and no later one]: \"x\ny\""
        )
        #expect(second == nil)
    }

    @Test("a printed input is ASCII, each scalar past it written as a Swift escape")
    func asciiOnly() {
        // `swift test` lost a whole first-failure line holding emoji and
        // Arabic scalars (step 6b's calibration, one seed of 20); the same
        // line written in ASCII arrived.
        let latch = FirstFailureLatch()

        let first = PBTTrace.firstFailureText("caf\u{E9} \u{1F44D}\u{600}", test: nil, latch: latch)
        let traced = PBTTrace.noteText("\u{FEFF}x", test: nil)

        #expect(first == "PBT first failing input, before shrinking [no test]: \"caf\\u{E9} \\u{1F44D}\\u{600}\"")
        #expect(traced == "PBT trace [no test]: \"\\u{FEFF}x\"")
    }

    @Test("each check a test runs prints its own first failing input")
    func firstFailurePerCheck() {
        // Two checks in one body, or one test repeated in one process: each
        // run of the body makes its own latch.
        let firstCheck = FirstFailureLatch()
        let secondCheck = FirstFailureLatch()

        let first = PBTTrace.firstFailureText(1, test: Test.current, latch: firstCheck)
        let second = PBTTrace.firstFailureText(2, test: Test.current, latch: secondCheck)

        #expect(first?.hasSuffix(": 1") == true)
        #expect(second?.hasSuffix(": 2") == true)
    }

    @Test("outside a test, the first failing input says so")
    func firstFailureOutsideTest() {
        let latch = FirstFailureLatch()

        let outside = PBTTrace.firstFailureText(2, test: nil, latch: latch)
        let outsideAgain = PBTTrace.firstFailureText(3, test: nil, latch: latch)

        #expect(outside == "PBT first failing input, before shrinking [no test]: 2")
        #expect(outsideAgain == nil)
    }

    @Test("a latch grants its first claim only, under concurrent claims")
    func latch() async {
        let latch = FirstFailureLatch()

        let granted = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<200 {
                group.addTask { latch.claim() }
            }
            return await group.reduce(into: 0) { total, claimed in
                total += claimed ? 1 : 0
            }
        }

        #expect(granted == 1)
        #expect(latch.claim() == false)
    }
}
