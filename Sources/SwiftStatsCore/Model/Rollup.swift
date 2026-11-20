//
//  Rollup.swift
//  SwiftStatsCore
//
//  Size, shape and complexity summarised over a module or the project
//  (PRD §7.2, §7.3): counts by kind and distributions of each measure.
//

/// Counts and distributions over one module, or over the project.
public struct Rollup: Codable, Hashable, Sendable {
    /// Whether this covers a module or the project.
    public let scope: RollupScope
    /// The module's name; for the project, `production` or `tests`.
    public let name: String
    /// Scanned files.
    public let files: Int
    /// Function records by kind (`FunctionKind` raw values).
    public let functions: [String: Int]
    /// Function records with a doc comment.
    public let documentedFunctions: Int
    /// `async` function records (PRD §7.4, concurrency shape).
    public let asyncFunctions: Int
    /// Type records by kind (`TypeKind` raw values), nested and local ones included.
    public let types: [String: Int]
    /// Stripped lines of every function record.
    public let functionLength: Distribution
    /// Parameter counts of `func`, `init` and `subscript` records.
    public let parameterCount: Distribution
    /// Maximum nesting depth of every scored record.
    public let maxNesting: Distribution
    /// Cognitive complexity of every scored record.
    public let cognitive: Distribution
    /// Decision count of every scored record.
    public let decisionCount: Distribution
    /// SwiftLint-compatible count of the records SwiftLint scores (`func`, `init`).
    public let swiftLintCompatible: Distribution
    /// Stripped lines of every type record.
    public let typeBodyLength: Distribution
    /// Member count of every type record.
    public let typeMemberCount: Distribution
    /// Stripped lines of every file.
    public let fileLength: Distribution
    /// Findings by tool, then rule; only tools that ran have an entry (PRD §7.16).
    public let findings: [String: [String: Int]]
    /// Findings by tool, then kind (`census`, `defect`); only tools that ran have an entry.
    public let findingKinds: [String: [String: Int]]
    /// Declarations by access level, documentation and `final` (PRD §7.5).
    public let api: APISurface
    /// Tests by framework and kind, and the test-to-code line counts (PRD §7.8).
    public let tests: TestSummary
    /// Side-effect tiers and purity verdicts (PRD §7.10); nil when
    /// SwiftEffectInference didn't run, and on test modules and the `tests` part.
    public let effects: EffectRollup?
    /// Law-check pairs by state (PRD §7.11); nil on test modules and the
    /// `tests` part, whose types are never subjects.
    public let laws: LawRollup?
}
