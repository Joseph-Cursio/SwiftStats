//
//  CallArgument.swift
//  SwiftStatsCore
//
//  One argument of a call a test writes, as a function's parameters fit it
//  (M5, `CallSignature`).
//

/// One argument of a call, as label fitting reads it.
struct CallArgument: Hashable, Sendable {
    /// Its label, without backticks; nil when it has none.
    let label: String?
    /// Whether it is the call's unlabelled trailing closure, which fits a
    /// parameter of any label.
    let isTrailingClosure: Bool
}
