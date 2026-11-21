import Probe
import XCTest

final class CounterXCTests: XCTestCase {
    func testEmptyCounter() {
        XCTAssertEqual(Counter().doubled(), 0)
    }
}
