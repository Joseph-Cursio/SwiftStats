import Foundation
@testable import SwiftStatsCore
import Testing

/// The old paths diff hunks are filed under, as git writes them: a path
/// git quotes reads back through every escape git writes, its letter
/// escapes `\a \b \t \n \v \f \r \" \\` and octal ones (design B34).
extension DiffHunkTests {
    @Test(
        """
        a path git quotes reads back through each escape git writes, letters and octal, so its hunks are filed \
        under the name git escaped (design B34)
        """,
        arguments: [
            ("x\\ay", "x\u{7}y"),
            ("x\\by", "x\u{8}y"),
            ("x\\ty", "x\ty"),
            ("x\\ny", "x\ny"),
            ("x\\vy", "x\u{B}y"),
            ("x\\fy", "x\u{C}y"),
            ("x\\ry", "x\ry"),
            ("x\\\"y", "x\"y"),
            ("x\\\\y", "x\\y"),
            ("x\\001y", "x\u{1}y"),
            ("x\\177y", "x\u{7F}y"),
            ("Caf\\303\\251", "Caf\u{E9}")
        ]
    )
    func quotedPaths(escaped: String, name: String) {
        // As git writes them (core.quotepath off): quoted, with C escapes.
        let diff = """
        diff --git "a/Pkg/\(escaped).swift" "b/Pkg/\(escaped).swift"
        index 7898192..f5f1a5f 100644
        --- "a/Pkg/\(escaped).swift"
        +++ "b/Pkg/\(escaped).swift"
        @@ -2 +2 @@
        -b
        +c

        """

        let hunks = GitChanges.hunks(inDiff: diff, packagePath: "Pkg")

        #expect(hunks == ["\(name).swift": [DiffHunk(start: 2, count: 1)]])
        #expect(hunks.keys.map { Array($0.unicodeScalars) } == [Array("\(name).swift".unicodeScalars)])
    }
}
