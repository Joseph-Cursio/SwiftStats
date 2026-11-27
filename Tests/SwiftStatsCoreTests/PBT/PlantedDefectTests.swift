import Testing

/// How a mutant meta-test judges a property's check (design D15): a check
/// that detects a planted defect's output passes the meta-test, and one
/// that leaves it undetected fails it, so the meta-test can't pass
/// vacuously.
@Suite("Planted defects")
struct PlantedDefectTests {
    @Test("a check that detects a planted defect's output passes the meta-test")
    func detected() {
        PlantedDefect.expectDetected("a defect the check detects", sourceLocation: #_sourceLocation) {
            Issue.record("a law fails")
            return false
        }
    }

    @Test("a check that leaves a planted defect's output undetected fails the meta-test twice")
    func undetected() {
        let recorded = AntecedentTally()

        withKnownIssue {
            PlantedDefect.expectDetected("a defect the check leaves undetected", sourceLocation: #_sourceLocation) {
                true
            }
        } matching: { issue in
            let text = String(describing: issue)
            if text.contains("Known issue was not recorded") {
                recorded.fire("nothing recorded")
            }
            if text.contains("the check left a planted defect undetected: a defect the check leaves undetected") {
                recorded.fire("check passed")
            }
            return true
        }

        #expect(recorded.summary == "check passed: 1, nothing recorded: 1")
    }
}
