//
//  FunctionKind.swift
//  SwiftStatsCore
//
//  The declaration kinds SwiftStats keeps a record for (PRD §6.1a). Closures,
//  protocol requirements without a body and macro expansions are deliberately
//  absent: their results fold into the enclosing record or are reported as
//  unmapped.
//

/// The kind of declaration a function record describes.
public enum FunctionKind: String, Codable, CaseIterable, Sendable {
    /// An explicit accessor (`get`, `set`, `willSet`, `didSet`, …) or the
    /// implicit getter of a computed property.
    case accessor
    /// A `deinit`.
    case deinitializer = "deinit"
    /// A `func`, including nested and operator functions.
    case function = "func"
    /// An `init`.
    case initializer = "init"
    /// A `subscript` with a body.
    case subscriptDeclaration = "subscript"
    /// The top-level statements of one file (for example `main.swift`).
    case topLevelCode = "topLevel"
}
