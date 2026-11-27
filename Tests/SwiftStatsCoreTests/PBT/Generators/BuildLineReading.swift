//
//  BuildLineReading.swift
//  SwiftStatsCoreTests
//
//  What a generated build-output line should read as, by the rules
//  `BuildOutputReader`'s and `BuildLineGrammar`'s doc comments state and
//  the user's decisions U10 and U13 settle: the label a property compares
//  the reader against. A header's label carries the whole diagnostic it
//  begins, so a property can compare diagnostics without re-reading the
//  lines.
//

@testable import SwiftStatsCore

/// What a generated build-output line reads as.
enum BuildLineReading: Hashable, Sendable {
    /// Taken into the message of the diagnostic above it.
    case continuation
    /// The first line of `diagnostic`.
    case diagnostic(BuildDiagnostic)
    /// A timing line, read as `entry` (standard error only).
    case entry(TimingEntry)
    /// Read, and neither kept nor counted.
    case ignored
    /// Counted among the lines starting `warning: ` that aren't
    /// diagnostics.
    case otherWarning
    /// Skipped as structure: blank, excerpt, box or decorated.
    case skipped
    /// Counted as a line holding `ms<TAB>` that states no entry.
    case unparsedTiming
    /// Not stated: a wild line, which may read as anything.
    case unstated
}
