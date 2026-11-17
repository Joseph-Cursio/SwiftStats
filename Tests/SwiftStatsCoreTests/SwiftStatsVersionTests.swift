import SwiftStatsCore
import Testing

@Suite("SwiftStatsVersion")
struct SwiftStatsVersionTests {
    @Test("current version is a three-part semantic version")
    func currentIsSemanticVersion() {
        let parts = SwiftStatsVersion.current.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { part in Int(part) != nil })
    }
}
