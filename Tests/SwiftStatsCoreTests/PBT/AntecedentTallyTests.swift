import Foundation
import Testing

/// How a conditional law counts its antecedents (design D14): each label's
/// firings are counted, safely across the engine's parallel runs; the
/// summary lists them in label order; and requiring a label records one
/// issue for each label that never fired, so a law that checked nothing
/// fails rather than passing vacuously.
@Suite("Antecedent tally")
struct AntecedentTallyTests {
    @Test("each label's firings are counted, and a label that never fired counts 0")
    func counts() {
        let tally = AntecedentTally()

        tally.fire("collides")
        tally.fire("refused")
        tally.fire("collides")

        #expect(tally.count("collides") == 2)
        #expect(tally.count("refused") == 1)
        #expect(tally.count("merged") == 0)
    }

    @Test("the summary lists each label and its count in label order")
    func summary() {
        let tally = AntecedentTally()
        #expect(tally.summary == "nothing fired")

        tally.fire("refused")
        tally.fire("collides")
        tally.fire("refused")

        #expect(tally.summary == "collides: 1, refused: 2")
    }

    @Test("firings from concurrent runs are all counted")
    func concurrent() async {
        let tally = AntecedentTally()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<1_000 {
                group.addTask { tally.fire(index.isMultiple(of: 4) ? "rare" : "common") }
            }
        }

        #expect(tally.count("rare") == 250)
        #expect(tally.count("common") == 750)
    }

    @Test("requiring labels that all fired records nothing")
    func requiredFired() {
        let tally = AntecedentTally()
        tally.fire("collides")
        tally.fire("refused")

        tally.requireFired(["collides", "refused"], sourceLocation: #_sourceLocation)
        tally.requireFired([], sourceLocation: #_sourceLocation)
    }

    @Test("requiring labels records one issue for each label that never fired, naming it")
    func requiredUnfired() {
        let tally = AntecedentTally()
        tally.fire("collides")
        let recorded = AntecedentTally()

        withKnownIssue {
            tally.requireFired(["collides", "merged", "refused"], sourceLocation: #_sourceLocation)
        } matching: { issue in
            let text = String(describing: issue)
            for label in ["collides", "merged", "refused"] where text.contains("\"\(label)\" never fired") {
                recorded.fire(label)
            }
            return text.contains("(collides: 1)")
        }

        #expect(recorded.summary == "merged: 1, refused: 1")
    }
}
