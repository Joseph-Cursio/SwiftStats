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
    public internal(set) var findings: [String: [String: Int]]
    /// Findings by tool, then kind (`census`, `defect`); only tools that ran have an entry.
    public internal(set) var findingKinds: [String: [String: Int]]
    /// Declarations by access level, documentation and `final` (PRD §7.5).
    public let api: APISurface
    /// Tests by framework and kind, and the test-to-code line counts (PRD
    /// §7.8), with the dead lines once the `periphery` collector ran (M7).
    public internal(set) var tests: TestSummary
    /// Side-effect tiers and purity verdicts (PRD §7.10); nil when
    /// SwiftEffectInference didn't run, and on test modules and the `tests` part.
    public let effects: EffectRollup?
    /// Law-check pairs by state (PRD §7.11); nil on test modules and the
    /// `tests` part, whose types are never subjects.
    public let laws: LawRollup?
    /// Property-test suggestions by tier, mapped and unmapped (PRD §7.11);
    /// nil when SwiftInferProperties didn't run, and on scopes holding none.
    public let properties: PropertyRollup?
    /// Clone classes with a copy in the scope, by kind, and the stripped
    /// lines copies cover (PRD §7.12); nil when SwiftCloneDetector didn't
    /// run, and on test modules and the `tests` part, which it doesn't read.
    public let clones: CloneRollup?
    /// Lines, regions, records and public functions by coverage (M5, PRD
    /// §7.8); nil when the coverage collector didn't run, and on test
    /// modules and the `tests` part, whose files it leaves out.
    public internal(set) var coverage: CoverageRollup?
    /// Mutants by verdict, SwiftMutator's score over them and functions by
    /// mutation state (M6, design §4); nil when the SwiftMutator collector
    /// left no results, and on test modules and the `tests` part, which it
    /// doesn't mutate.
    public internal(set) var mutation: MutationRollup?
    /// Records by USR: with one, without one by reason, in a disagreement
    /// (M7, design §3.4); nil when the `index` collector didn't run. Every
    /// scope has it, test modules and the `tests` part included.
    public internal(set) var index: IndexRollup?
    /// Dead records per run and the unused production declarations by
    /// kind (M7, design §5.4, §10.3); nil when the `periphery` collector
    /// didn't run, and on test modules and the `tests` part, whose entries
    /// it leaves out.
    public internal(set) var deadCode: DeadCodeRollup?
    /// Type-check time, the slowest record and expression, and the records
    /// timed (M7, design §6.4); nil when the `build` collector didn't run.
    /// Every scope has it, test modules and the `tests` part included.
    public internal(set) var typecheck: TypeCheckRollup?

    /// The roll-up with `coverage` as its coverage.
    func with(coverage: CoverageRollup?) -> Self {
        var rollup = self
        rollup.coverage = coverage
        return rollup
    }

    /// The roll-up with `deadCode` as its dead-code counts.
    func with(deadCode: DeadCodeRollup?) -> Self {
        var rollup = self
        rollup.deadCode = deadCode
        return rollup
    }

    /// The roll-up with `deadLines` as its line ratio's dead lines.
    func with(deadLines: Int?) -> Self {
        var rollup = self
        rollup.tests.lineRatio = tests.lineRatio.with(deadLines: deadLines)
        return rollup
    }

    /// The roll-up with `rules` and `kinds` as tool `tool`'s finding
    /// counts by rule and by kind.
    func with(findings rules: [String: Int], kinds: [String: Int], of tool: String) -> Self {
        var rollup = self
        rollup.findings[tool] = rules
        rollup.findingKinds[tool] = kinds
        return rollup
    }

    /// The roll-up with `index` as its USR counts.
    func with(index: IndexRollup?) -> Self {
        var rollup = self
        rollup.index = index
        return rollup
    }

    /// The roll-up with `typecheck` as its type-check figures.
    func with(typecheck: TypeCheckRollup?) -> Self {
        var rollup = self
        rollup.typecheck = typecheck
        return rollup
    }

    /// The roll-up with `mutation` as its mutation results.
    func with(mutation: MutationRollup?) -> Self {
        var rollup = self
        rollup.mutation = mutation
        return rollup
    }
}
