@testable import SwiftStatsCore
import Testing

/// Globs for `excluded` (PRD §10.1).
@Suite("Glob patterns")
struct GlobPatternTests {
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
}
