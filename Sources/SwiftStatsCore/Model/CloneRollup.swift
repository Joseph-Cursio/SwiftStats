//
//  CloneRollup.swift
//  SwiftStatsCore
//
//  Clone counts over a production module or the project's production part
//  (PRD §7.12): the classes with a copy in the scope, by kind, and the
//  stripped lines its copies cover, counted once however many copies
//  overlap there, so the production part's count is a union, not a sum.
//  Absent from test modules and the `tests` part, which aren't scanned.
//

/// Clone classes and cloned lines counted over one scope.
public struct CloneRollup: Codable, Hashable, Sendable {
    /// Classes with a copy in the scope, by kind.
    public struct Classes: Codable, Hashable, Sendable {
        /// Subtree classes whose copies are token-identical.
        public let exact: Int
        /// Subtree classes with identifiers or literals renamed.
        public let renamed: Int
        /// Sequence classes.
        public let sequence: Int
        /// Near-miss classes.
        public let nearMiss: Int
    }

    /// Classes with a copy in the scope.
    public let classes: Classes
    /// Stripped lines of the scope's files that any copy covers.
    public let clonedLines: Int

    /// The counts of `report`'s classes with a copy in `paths`, and of the
    /// lines `linesByFile` says copies cover there.
    init(_ report: CloneReport, linesByFile: [String: Set<Int>], in paths: Set<String>) {
        let held = report.classes.filter { cloneClass in
            cloneClass.instances.contains { paths.contains($0.file) }
        }
        let count = { (matches: (CloneClass) -> Bool) in
            held.filter(matches).count
        }
        classes = Classes(
            exact: count { $0.pass == .subtree && $0.exact },
            renamed: count { $0.pass == .subtree && $0.exact == false },
            sequence: count { $0.pass == .sequence },
            nearMiss: count { $0.pass == .nearMiss }
        )
        clonedLines = paths.reduce(0) { total, path in total + (linesByFile[path]?.count ?? 0) }
    }
}
