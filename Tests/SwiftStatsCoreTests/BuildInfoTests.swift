import Foundation
import SwiftStatsBuildInfo
@testable import SwiftStatsCore
import Testing

/// SwiftStats' own build identity, embedded by BuildInfoPlugin (PRD §6.2).
@Suite("Build info")
struct BuildInfoTests {
    /// The SwiftStats checkout these tests were built from.
    private static let checkout = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test(
        "a build from a git checkout embeds its commit and a build-input hash",
        .enabled(if: GitReader.isTopLevel(checkout), "needs a git checkout of SwiftStats")
    )
    func embedded() throws {
        let head = try #require(GitReader.line(["rev-parse", "HEAD"], in: Self.checkout))

        #expect(SwiftStatsBuildInfo.commit == head)
        #expect(SwiftStatsBuildInfo.inputHash.count == 64)
    }
}
