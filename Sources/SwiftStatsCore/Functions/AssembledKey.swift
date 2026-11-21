//
//  AssembledKey.swift
//  SwiftStatsCore
//
//  A key built from the collector's open scopes.
//

/// A record key and what it hangs from.
struct AssembledKey {
    /// The key (PRD §6.1).
    let key: String
    /// The parent record's key, when the innermost prefix is a record.
    let parentKey: String?
    /// Whether the key has a record or context prefix, which is when local
    /// declarations of one name need numbering.
    let isNested: Bool
    /// The enclosing types' names joined by dots; nil at the top level and
    /// inside a record or context.
    let typePath: String?
    /// Whether an enclosing type is `private` or `fileprivate` (not merely
    /// a `private extension` of a type others see).
    let isTypeFileScoped: Bool
}
