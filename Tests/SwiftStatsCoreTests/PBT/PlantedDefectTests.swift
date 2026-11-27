import Testing

/// How a mutant meta-test judges a property's check (design D15): a check
/// that catches a planted defect's output passes the meta-test, and one
/// that lets it through fails it, so the meta-test can't pass vacuously.
@Suite("Planted defects")
struct PlantedDefectTests {
    @Test("a check that catches a planted defect's output passes the meta-test")
    func caught() {
        PlantedDefect.expectCaught("a defect the check catches", sourceLocation: #_sourceLocation) {
            Issue.record("a law fails")
            return false
        }
    }

    @Test("a check that lets a planted defect's output through fails the meta-test twice")
    func missed() {
        let recorded = AntecedentTally()

        withKnownIssue {
            PlantedDefect.expectCaught("a defect the check misses", sourceLocation: #_sourceLocation) { true }
        } matching: { issue in
            let text = String(describing: issue)
            if text.contains("Known issue was not recorded") {
                recorded.fire("nothing recorded")
            }
            if text.contains("the check let a planted defect through: a defect the check misses") {
                recorded.fire("check passed")
            }
            return true
        }

        #expect(recorded.summary == "check passed: 1, nothing recorded: 1")
    }
}
