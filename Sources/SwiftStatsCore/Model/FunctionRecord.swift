//
//  FunctionRecord.swift
//  SwiftStatsCore
//
//  One row per function (PRD §6.1). The key is the permanent identity; file,
//  range and body hash are attributes, so moving or reformatting a function
//  changes them without changing who it is.
//

/// A single function-like declaration and its syntax-only (T0) facts.
public struct FunctionRecord: Codable, Hashable, Sendable {
    /// The syntactic identity key (PRD §6.1).
    public let key: String
    /// The target (module) the declaration belongs to.
    public let module: String
    /// What kind of declaration this is.
    public let kind: FunctionKind
    /// The declared name: the function or property name, `init`, `deinit`,
    /// `subscript`, or `<top-level>`.
    public let name: String
    /// For accessors, the accessor keyword (`get`, `set`, `didSet`, …).
    public let accessorKind: String?
    /// Path of the file, relative to the package root.
    public let file: String
    /// The declaration's source range, attributes included.
    public let range: SourceSpan
    /// Lines that hold at least one token of the declaration, attributes
    /// (nested ones included) and comments excluded (PRD §7.2).
    public let strippedLines: Int
    /// Stripped lines of the body alone, without its opening and closing
    /// braces: 1 for `{ true }` however it is laid out (PRD §6.6).
    public let bodyLines: Int
    /// Parameters in the declaration's own parameter list, for `func`, `init`
    /// and `subscript`; nil for kinds without one.
    public let parameterCount: Int?
    /// Whether the declaration has a doc comment (`///` or `/** */`); for an
    /// accessor, the property or subscript it belongs to.
    public let isDocumented: Bool
    /// Whether the declaration is `async`: a `func` or `init` marked so, or
    /// an `async` getter (PRD §7.4, concurrency shape).
    public let isAsync: Bool
    /// Complexity scores from SwiftCodeMetrics (PRD §7.3). Nil for a
    /// `subscript` with explicit accessors, which carry the scores, and when
    /// the library gave no score for the record, which the scan warns about.
    public internal(set) var complexity: FunctionComplexity?
    /// Hash of the body's tokens with comments and whitespace removed, so
    /// reformatting leaves it unchanged.
    public let bodyHash: String
    /// Key of the enclosing record, for nested functions and for accessors
    /// of a subscript.
    public let parentKey: String?
    /// The `#if` condition the declaration sits under, if any.
    public let ifConfig: String?
    /// Production code, a test, or a test-target helper.
    public let role: CodeRole
    /// What SwiftEffectInference says about the record (PRD §7.10): set on
    /// production `func`s, computed-property getters and `subscript`s when
    /// the collector ran; nil for every other record, and when it didn't.
    public internal(set) var effect: EffectFacts?

    /// Creates a record. Fields are documented on their properties.
    public init(
        key: String,
        module: String,
        kind: FunctionKind,
        name: String,
        accessorKind: String?,
        file: String,
        range: SourceSpan,
        strippedLines: Int,
        bodyLines: Int,
        parameterCount: Int?,
        isDocumented: Bool,
        isAsync: Bool,
        bodyHash: String,
        parentKey: String?,
        ifConfig: String?,
        role: CodeRole
    ) {
        self.key = key
        self.module = module
        self.kind = kind
        self.name = name
        self.accessorKind = accessorKind
        self.file = file
        self.range = range
        self.strippedLines = strippedLines
        self.bodyLines = bodyLines
        self.parameterCount = parameterCount
        self.isDocumented = isDocumented
        self.isAsync = isAsync
        self.bodyHash = bodyHash
        self.parentKey = parentKey
        self.ifConfig = ifConfig
        self.role = role
    }
}
