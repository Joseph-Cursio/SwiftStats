//
//  ModuleTime.swift
//  SwiftStatsCore
//
//  A module's type-check time as the report's Build and index section
//  totals it (M7, design §6.2, §10.1): function-body milliseconds without
//  the records nested in a body, the records timed, and the slowest
//  expression.
//

/// One module's (or project part's) type-check figures.
struct ModuleTime {
    /// What separates a type attachment's module from its type path.
    static let moduleSeparator = "::"

    /// Function-body time, in whole milliseconds, nested records left out.
    var milliseconds = 0
    /// Records with a timing entry.
    var timed = 0
    /// The slowest expression, in whole milliseconds; nil when none was
    /// timed.
    var slowest: Int?

    /// Both figures added together, the slower expression kept.
    func adding(_ other: Self) -> Self {
        Self(
            milliseconds: milliseconds + other.milliseconds,
            timed: timed + other.timed,
            slowest: [slowest, other.slowest].compactMap(\.self).max()
        )
    }
}
