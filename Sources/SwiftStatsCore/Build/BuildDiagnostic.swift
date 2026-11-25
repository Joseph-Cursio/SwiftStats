//
//  BuildDiagnostic.swift
//  SwiftStatsCore
//
//  One compiler diagnostic of the T1 build's output (M7, design §6.1): its
//  severity, where the compiler put it, its message with continuation lines
//  joined and its trailing ` [<diagnostic ID>]` and ` [#<group>]` taken
//  off, the ID `-debug-diagnostic-names` appends and the group, and, for a
//  diagnostic inside a macro expansion, the place of its `expanded code
//  originates here` note.
//

/// A diagnostic the build printed.
struct BuildDiagnostic: Hashable, Sendable {
    /// Where the compiler put a diagnostic.
    enum Location: Hashable, Sendable {
        /// A file, or a module interface's buffer named like one.
        case file(BuildPlace)
        /// A macro expansion's buffer: the macro's name (`#expect`,
        /// `@Test`), a line and a column in the expansion.
        case macro(name: String, line: Int, column: Int)
        /// `<unknown>`, with the line printed.
        case unknown(line: Int)
    }

    /// A diagnostic's severity.
    enum Severity: String, CaseIterable, Sendable {
        /// An error.
        case error
        /// A note.
        case note
        /// A remark.
        case remark
        /// A warning.
        case warning
    }

    /// Its severity.
    let severity: Severity
    /// Where the compiler put it.
    let location: Location
    /// The message, continuation lines joined with newlines, without its
    /// ID and group suffixes.
    let message: String
    /// The diagnostic ID (`pbd_never_used`); nil when none was printed.
    let identifier: String?
    /// The diagnostic group (`NoUsage`); nil for an ungrouped diagnostic.
    let group: String?
    /// For a diagnostic in a macro expansion, the place its origin note
    /// names; nil otherwise, or when no origin note followed.
    let origin: BuildPlace?
}
