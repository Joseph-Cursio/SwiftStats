//
//  MutationRunFacts.swift
//  SwiftStatsCore
//
//  What a results file's headers say about the run (M6, design §2 item
//  11): the build, toolchain and settings from its first header, and from
//  its last the ones a resume can change (fail-fast, how many mutants
//  were discovered and dropped), and the workers and time limit from the
//  last session that tested a mutant.
//

/// A SwiftMutator run's facts, from its results file's headers.
struct MutationRunFacts: Equatable, Sendable {
    /// When the first session started, as SwiftMutator wrote it (ISO 8601,
    /// UTC).
    let startedAt: String
    /// The SHA-256 of SwiftMutator's executable, which identifies its
    /// build; nil when not recorded.
    let executableSHA256: String?
    /// SwiftMutator's version (`0.1.0` for every build).
    let version: String
    /// What the test command printed for its version.
    let testCommandVersion: String?
    /// The SHA-256 of a test command that wraps `swift`.
    let testExecutableSHA256: String?
    /// `SDKROOT`, `DEVELOPER_DIR` and `TOOLCHAINS` as set.
    let sdkEnvironment: [String: String]
    /// The operators asked for, sorted.
    let operators: [String]
    /// Whether coverage was off.
    let skipCoverage: Bool
    /// How many mutants were tested at once, by the last session that
    /// tested any (else the first session's count).
    let workers: Int
    /// The time limit per mutant, in seconds, of the last session that
    /// tested any (else the first session's); nil when not recorded.
    let timeoutSeconds: Double?
    /// Whether the last session stopped a mutant's tests at the first
    /// failure.
    let stopsAtFirstFailure: Bool
    /// How many mutants the last session discovered.
    let mutantsDiscovered: Int
    /// How many the last session couldn't test (`#if`, nowhere to switch).
    let mutantsDropped: Int?
    /// What a `--since` run chose.
    let since: MutationSince?
}
