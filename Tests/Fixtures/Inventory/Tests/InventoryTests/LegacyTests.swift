@testable import Inventory
import XCTest

final class LegacyTests: XCTestCase {
    func testScreen() {
        XCTAssertNotNil(Screen())
        XCTAssertEqual(1, 1)
    }

    func testNothing() {
    }

    func helperNotATest() { }
}
