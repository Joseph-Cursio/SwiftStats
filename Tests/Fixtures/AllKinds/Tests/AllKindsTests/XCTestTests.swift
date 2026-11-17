import AllKinds
import XCTest

class BaseTestCase: XCTestCase {
    func makeResource() -> Resource { Resource(handle: 1) }
}

final class ResourceTests: BaseTestCase {
    func testDescribe() {
        XCTAssertFalse(makeResource().describe().isEmpty)
    }

    func testWithArgument(_ value: Int) { }
}

extension ResourceTests {
    func testFromExtension() {
        XCTAssertEqual(makeResource().load(), 1)
    }
}
