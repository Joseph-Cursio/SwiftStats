//
//  DiagnosticHeader.swift
//  SwiftStatsCore
//
//  A diagnostic's first line in the T1 build's output (M7, design §6.1):
//  where the compiler put it, its severity, and the start of its message,
//  which continuation lines may extend.
//

/// A diagnostic's first line, read.
struct DiagnosticHeader: Hashable, Sendable {
    /// Where the compiler put the diagnostic.
    let location: BuildDiagnostic.Location
    /// Its severity.
    let severity: BuildDiagnostic.Severity
    /// The message's first line, its suffixes still on it.
    let message: Substring
}
