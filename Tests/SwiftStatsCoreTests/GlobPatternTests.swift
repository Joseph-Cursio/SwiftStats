@testable import SwiftStatsCore
import Testing

/// Globs for `excluded` (PRD §10.1), every match extending to the paths
/// under it, and their stars, in runs or split by other text, which match
/// what they always matched but can't make a failed match take exponential
/// time (design B4, B27).
@Suite("Glob patterns")
struct GlobPatternTests {
    /// Stars in the long run: under the regular expression, before B4
    /// collapsed star runs, 24 took about 4 s to fail against 12 `b`s, and
    /// each extra pair about five times as long. Sized so that a
    /// backtracking matcher fails the bound in seconds rather than running
    /// for hours; the direct matcher (B27) now keeps it.
    private static let starRun = 24
    /// `b`s the long run of stars fails to match.
    private static let starPathLength = 12
    /// `**/` pieces in the long folder run: under the regular expression,
    /// before B4 collapsed star runs, 14 took about 6 s to fail against as
    /// many folders, and each extra one about four times as long. Sized as
    /// `starRun` is.
    private static let folderRun = 14
    /// `***/` pieces in the repeated odd run: under the regular expression,
    /// before B4 turned an odd run's `.*` into `(.*/)?`, 14 took 22 s to
    /// fail against as many folders, and each two extra about fifteen times
    /// as long. Sized as `starRun` is.
    private static let oddRun = 14
    /// The most a failed match of a long run may take.
    private static let matchBound = Duration.seconds(1)
    /// `*?` pieces failing against `splitPathLength` `a`s: the regular
    /// expression took 13.7 s to fail with 10 (design B27), and each extra
    /// one about four times as long.
    private static let pairRepeats = 10
    /// `a`s the repeated split stars fail to match.
    private static let splitPathLength = 30
    /// `**/*/` pieces failing against twice as many folders: the regular
    /// expression took 2.6 s with 12, and each two extra about fifteen times
    /// as long.
    private static let folderStarRepeats = 12
    /// `*/**` pieces failing against `starFolderCount` folders: the regular
    /// expression took 2.5 s with 10, and each extra one about three times
    /// as long.
    private static let starFolderRepeats = 10
    /// Folders the repeated `*/**` fails to match.
    private static let starFolderCount = 28
    /// `**a` pieces failing against `splitPathLength` `a`s: the regular
    /// expression took 3.9 s with 9, and each extra one about four times as
    /// long.
    private static let starLetterRepeats = 9
    /// `*?**a` pieces, two of B27's forms in turn, failing against
    /// `mixedPathLength` `a`s: the regular expression took 3.5 s to fail
    /// with 4, and 14.4 s with 5 against 30 `a`s.
    private static let mixedRepeats = 4
    /// `a`s the mixed glob fails to match.
    private static let mixedPathLength = 36

    /// Globs whose stars are split by other text, each with a path it fails
    /// to match: B27's four forms, sized as `starRun` is.
    private static let splitStars: [(glob: String, path: String)] = [
        (
            String(repeating: "*?", count: pairRepeats) + "x",
            String(repeating: "a", count: splitPathLength)
        ),
        (
            String(repeating: "**/*/", count: folderStarRepeats) + "a",
            String(repeating: "b/", count: 2 * folderStarRepeats) + "c"
        ),
        (
            String(repeating: "*/**", count: starFolderRepeats) + "/a",
            String(repeating: "b/", count: starFolderCount) + "b"
        ),
        (
            String(repeating: "**a", count: starLetterRepeats) + "x",
            String(repeating: "a", count: splitPathLength)
        )
    ]

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

    @Test("a wildcard pattern also matches everything under what it matches")
    func wildcardFolders() {
        #expect(GlobPattern("a*").matches("ab/c"))
        #expect(GlobPattern("Gen*").matches("Generated/x.swift"))
        #expect(GlobPattern("Sources/?").matches("Sources/A/B.swift"))
        #expect(GlobPattern("Gen*").matches("Sources/Generated/x.swift") == false)
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

    @Test("a glob whose stars are split by other text fails to match in well under a second", arguments: splitStars)
    func splitStarForms(glob: String, path: String) {
        let pattern = GlobPattern(glob)
        var matched = true
        let elapsed = ContinuousClock().measure {
            matched = pattern.matches(path)
        }
        #expect(matched == false)
        #expect(elapsed < Self.matchBound)
    }

    @Test("a glob of 4 *?**a pieces fails to match 36 a's in well under a second")
    func mixedSplitStars() {
        let glob = GlobPattern(String(repeating: "*?**a", count: Self.mixedRepeats) + "x")
        let path = String(repeating: "a", count: Self.mixedPathLength)
        var matched = true
        let elapsed = ContinuousClock().measure {
            matched = glob.matches(path)
        }
        #expect(matched == false)
        #expect(elapsed < Self.matchBound)
    }
}
