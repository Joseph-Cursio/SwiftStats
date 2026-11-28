@testable import SwiftStatsCore
import Testing

/// Hunk headers git never writes: one holding no range is skipped, not
/// read past its end.
extension DiffHunkTests {
    @Test("a hunk header holding no range is skipped, not a trap, and the next header reads")
    func headerWithoutRange() {
        let diff = """
        diff --git a/x.swift b/x.swift
        --- a/x.swift
        +++ b/x.swift
        @@\u{20}
        @@ -3 +3 @@
        -a
        +b

        """

        #expect(GitChanges.hunks(inDiff: diff, packagePath: "") == ["x.swift": [DiffHunk(start: 3, count: 1)]])
    }
}
