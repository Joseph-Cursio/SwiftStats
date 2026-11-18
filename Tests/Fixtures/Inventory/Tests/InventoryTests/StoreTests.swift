@testable import Inventory
import Testing

@Test func emptyStore() async {
    #expect(await Store().items.isEmpty)
}

@Test(arguments: [1, 2, 3])
func counts(value: Int) {
    #expect(value > 0)
    #expect(value < 4)
}

@Test(arguments: 0..<5, ["a", "b"])
func pairs(index: Int, name: String) {
    #expect(index >= 0)
}

@Test(arguments: Mode.allCases)
func modes(mode: Mode) { }

@Test func roundTrip() async {
    await propertyCheck(count: 50, input: Gen.int()) { value in
        #expect(value == value)
    }
}

@Test func idempotentSave() {
    #assertIdempotent { save() }
}

@PropertyLawSuite
struct StoreLaws { }

enum Mode: CaseIterable {
    case fast, slow
}

func save() -> Int { 1 }
