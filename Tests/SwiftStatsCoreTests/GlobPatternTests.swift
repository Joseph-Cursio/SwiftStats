@testable import SwiftStatsCore
import Testing

/// Globs for `excluded` (PRD §10.1), and their runs of stars, which
/// match what they always matched but can't make a failed match backtrack
/// exponentially.
@Suite("Glob patterns")
struct GlobPatternTests {
    /// Stars in the long run: before runs were collapsed, 24 took about 4 s
    /// to fail against 12 `b`s, and each extra pair about five times as
    /// long. Sized so that without the fix the test fails its bound in
    /// seconds rather than running for hours.
    private static let starRun = 24
    /// `b`s the long run of stars fails to match.
    private static let starPathLength = 12
    /// `**/` pieces in the long folder run: before runs were collapsed, 14
    /// took about 6 s to fail against as many folders, and each extra one
    /// about four times as long. Sized as `starRun` is.
    private static let folderRun = 14
    /// `***/` pieces in the repeated odd run: before an odd run's `.*` became
    /// `(.*/)?`, 14 took 22 s to fail against as many folders, and each
    /// two extra about fifteen times as long.
    private static let oddRun = 14
    /// The most a failed match of a long run may take.
    private static let matchBound = Duration.seconds(1)

    @Test("* and ? stay within a component; ** spans components")
    func wildcards() {
        #expect(GlobPattern("Sources/*.swift").matches("Sources/A.swift"))
        #expect(GlobPattern("Sources/*.swift").matches("Sources/Lib/A.swift") == false)
        #expect(GlobPattern("Sources/?.swift").matches("Sources/A.swift"))
        #expect(GlobPattern("**/Generated/*.swift").matches("Sources/Lib/Generated/A.swift"))
        #expect(GlobPattern("**/Generated/*.swift").matches("Generated/A.swift"))
        #expect(GlobPattern("Sources/**").matches("Sources/Lib/Deep/A.swift"))
    }

    @Test("a plain path matches itself and everything under it")
    func folders() {
        #expect(GlobPattern("Sources/Generated").matches("Sources/Generated/A.swift"))
        #expect(GlobPattern("./Sources/Generated/").matches("Sources/Generated/A.swift"))
        #expect(GlobPattern("Sources/Gen").matches("Sources/Generated/A.swift") == false)
        #expect(GlobPattern("Sources/A.swift").matches("Sources/A.swift"))
    }

    @Test(
        "a run of stars matches what its stars matched one by one",
        arguments: [
            ("**/a", "a", true),
            ("**/a", "x/y/a", true),
            ("**/a", "xa", false),
            ("**/**/a", "a", true),
            ("**/**/a", "x/y/a", true),
            ("**/**/a", "xa", false),
            ("***/a", "a", false),
            ("***/a", "x/y/a", true),
            ("****/a", "a", true),
            ("****/a", "xa", true),
            ("**/**b", "xb", true),
            ("x/**", "x/a\nb", false),
            ("x/***", "x/a\nb", true),
            ("x/****", "x/a\nb", false),
            ("***/***/a", "x/y/a", true),
            ("***/***/a", "x/a", false),
            ("a***", "a/b/c", true),
            ("***?", "", false),
            ("***?", "a/b", true),
            ("***/a", "x\ny/a", true)
        ]
    )
    func starRuns(pattern: String, path: String, matches: Bool) {
        #expect(GlobPattern(pattern).matches(path) == matches)
    }

    @Test("a run of 24 stars fails to match 12 b's in well under a second")
    func longStarRun() {
        let glob = GlobPattern(String(repeating: "*", count: Self.starRun) + "a")
        let path = String(repeating: "b", count: Self.starPathLength)
        var matched = true
        let elapsed = ContinuousClock().measure {
            matched = glob.matches(path)
        }
        #expect(matched == false)
        #expect(elapsed < Self.matchBound)
    }

    @Test("a run of 14 **/ pieces fails to match 14 folders in well under a second")
    func longFolderRun() {
        let glob = GlobPattern(String(repeating: "**/", count: Self.folderRun) + "a")
        let path = String(repeating: "b/", count: Self.folderRun) + "c"
        var matched = true
        let elapsed = ContinuousClock().measure {
            matched = glob.matches(path)
        }
        #expect(matched == false)
        #expect(elapsed < Self.matchBound)
    }

    @Test("a run of 14 ***/ pieces fails to match 14 folders in well under a second")
    func repeatedOddRun() {
        let glob = GlobPattern(String(repeating: "***/", count: Self.oddRun) + "a")
        let path = String(repeating: "b/", count: Self.oddRun) + "c"
        var matched = true
        let elapsed = ContinuousClock().measure {
            matched = glob.matches(path)
        }
        #expect(matched == false)
        #expect(elapsed < Self.matchBound)
    }
}
