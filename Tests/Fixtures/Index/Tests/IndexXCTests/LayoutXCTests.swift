import IndexCore
import XCTest

/// XCTest tests: `@objc`, so their USRs are `c:` USRs.
final class LayoutXCTests: XCTestCase {
    /// The layout of a width of 1.
    func testLayout() {
        XCTAssertEqual(layout(1), 9)
    }
}
