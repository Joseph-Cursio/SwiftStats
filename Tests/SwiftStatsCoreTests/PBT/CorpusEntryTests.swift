import Testing

/// How a property's shrunk counterexample is kept (design D8): as a literal
/// input beside the defect it pins, replayed by a parameterized example,
/// whose report names each case by that defect.
@Suite("Corpus entries")
struct CorpusEntryTests {
    /// Two entries of the shape a property's regressions take.
    static let entries = [
        CorpusEntry(input: "92233720368547759ms\t<invalid loc>", pins: "B1: a 17-digit timing traps"),
        CorpusEntry(input: "", pins: "B0: an empty log")
    ]

    @Test("an entry is named in a test report by the defect it pins", arguments: entries)
    func described(entry: CorpusEntry<String>) {
        #expect(String(describingForTest: entry) == entry.pins)
        #expect(entry.testDescription == entry.pins)
    }

    @Test("an entry carries its input unchanged into a parameterized example")
    func input() {
        #expect(Self.entries.map(\.input) == ["92233720368547759ms\t<invalid loc>", ""])
        #expect(Self.entries.map(\.pins) == ["B1: a 17-digit timing traps", "B0: an empty log"])
    }
}
