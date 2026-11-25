//
//  BuildOutput.swift
//  SwiftStatsCore
//
//  What `BuildOutputReader` read from the T1 build's two output files (M7,
//  design §6.1): the timing entries of its standard error in order, the
//  unique diagnostics of both files in the order first seen, and the
//  counters the independent checker accounts for.
//

/// The T1 build's output, read.
struct BuildOutput: Hashable, Sendable {
    /// Every timing entry of the standard error, in order; nothing is
    /// deduplicated (the emit-module job's second check counts too).
    let entries: [TimingEntry]
    /// Every distinct diagnostic of both files, standard error first, in
    /// the order first seen.
    let diagnostics: [BuildDiagnostic]
    /// Lines of either file that held an ANSI or OSC-8 escape sequence.
    let escapedLines: Int
    /// Lines of the standard error holding `ms<TAB>` that state no timing
    /// entry (expected 0).
    let unparsedTimingLines: Int
    /// Lines of either file starting `warning: ` that aren't diagnostics:
    /// Swift Build's summary form, the manifest commands `-v` prints as
    /// warnings, and SwiftPM's own package warnings.
    let otherWarningLines: Int
}
