//
//  DiffHunk.swift
//  SwiftStatsCore
//
//  The old side of one hunk of a zero-context `git diff` between an
//  earlier snapshot's commit and the current one (`@@ -start,count …`):
//  the lines of the earlier file the hunk replaces, or, with a count of
//  zero, the line after which it inserts.
//

/// The old-side range of a diff hunk.
public struct DiffHunk: Hashable, Sendable {
    /// The first old line it replaces; for a pure insertion, the line it
    /// inserts after (0 before the first).
    public let start: Int
    /// How many old lines it replaces; 0 for a pure insertion.
    public let count: Int

    /// A hunk replacing `count` old lines from `start`.
    public init(start: Int, count: Int) {
        self.start = start
        self.count = count
    }

    /// Whether the hunk touches lines `lower...upper` of the earlier file:
    /// a replacement when the lines it replaces meet them; a pure insertion
    /// when it inserts after a line from `lower` up to, not including,
    /// `upper`, so inside the range rather than before or after it.
    func overlaps(lower: Int, upper: Int) -> Bool {
        guard count >= 1 else {
            return lower <= start && start < upper
        }
        return start <= upper && start + count - 1 >= lower
    }
}
