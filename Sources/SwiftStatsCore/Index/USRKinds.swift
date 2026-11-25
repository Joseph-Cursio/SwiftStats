//
//  USRKinds.swift
//  SwiftStatsCore
//
//  Which index symbols the USR join reads, and which record each can name
//  (M7, design §3.1, §3.2). Function-like symbols are functions and
//  methods of any subkind, initializers, deinitializers and subscripts. A
//  `func` record takes a function or method with no subkind or an
//  operator's; an `init` record a constructor, a `deinit` record a
//  destructor; a `subscript` record a subscript; an accessor record a
//  function or method whose accessor subkind matches its accessor keyword
//  (a global or local computed variable's accessors are functions, a
//  member's are methods); top-level code none.
//

/// The index symbol kinds the USR join reads.
enum USRKinds {
    /// The method kinds, the function kind included (a global or local
    /// computed variable's accessors are functions).
    static let functionKinds: Set<Int> = [
        IndexSymbolKind.function, IndexSymbolKind.instanceMethod, IndexSymbolKind.classMethod,
        IndexSymbolKind.staticMethod
    ]
    /// The property kinds, a subscript's.
    private static let propertyKinds: Set<Int> = [
        IndexSymbolKind.instanceProperty, IndexSymbolKind.classProperty, IndexSymbolKind.staticProperty
    ]
    /// The operator subkinds, which a `func` record matches as it matches
    /// no subkind.
    private static let operatorSubkinds: Set<Int> = [
        IndexSymbolKind.Subkind.swiftPrefixOperator, IndexSymbolKind.Subkind.swiftPostfixOperator,
        IndexSymbolKind.Subkind.swiftInfixOperator
    ]
    /// The accessor subkind each accessor keyword matches.
    private static let accessorSubkinds: [String: Int] = [
        "get": IndexSymbolKind.Subkind.accessorGetter,
        "set": IndexSymbolKind.Subkind.accessorSetter,
        "willSet": IndexSymbolKind.Subkind.swiftAccessorWillSet,
        "didSet": IndexSymbolKind.Subkind.swiftAccessorDidSet,
        "_read": IndexSymbolKind.Subkind.swiftAccessorRead,
        "read": IndexSymbolKind.Subkind.swiftAccessorRead,
        "_modify": IndexSymbolKind.Subkind.swiftAccessorModify,
        "modify": IndexSymbolKind.Subkind.swiftAccessorModify,
        "unsafeAddress": IndexSymbolKind.Subkind.swiftAccessorAddressor,
        "unsafeMutableAddress": IndexSymbolKind.Subkind.swiftAccessorMutableAddressor,
        "init": IndexSymbolKind.Subkind.swiftAccessorInit
    ]

    /// Whether `occurrence`'s symbol is function-like: a function or
    /// method of any subkind, an initializer, a deinitializer or a
    /// subscript.
    static func isFunctionLike(_ occurrence: IndexOccurrenceFact) -> Bool {
        functionKinds.contains(occurrence.kind)
            || occurrence.kind == IndexSymbolKind.constructor
            || occurrence.kind == IndexSymbolKind.destructor
            || propertyKinds.contains(occurrence.kind) && occurrence.subkind == IndexSymbolKind.Subkind.swiftSubscript
    }

    /// Whether `kind` is a property kind: an instance, class or static
    /// property, or a subscript.
    static func isProperty(_ kind: Int) -> Bool {
        propertyKinds.contains(kind)
    }

    /// Whether a definition of `occurrence`'s symbol can be `record`'s
    /// primary USR (design §3.2).
    static func isCompatible(_ record: FunctionRecord, with occurrence: IndexOccurrenceFact) -> Bool {
        let (kind, subkind) = (occurrence.kind, occurrence.subkind)
        switch record.kind {
        case .function:
            return functionKinds.contains(kind)
                && (subkind == IndexSymbolKind.Subkind.plain || operatorSubkinds.contains(subkind))

        case .initializer:
            return kind == IndexSymbolKind.constructor

        case .deinitializer:
            return kind == IndexSymbolKind.destructor

        case .subscriptDeclaration:
            return propertyKinds.contains(kind) && subkind == IndexSymbolKind.Subkind.swiftSubscript

        case .accessor:
            guard let wanted = record.accessorKind.flatMap({ accessorSubkinds[$0] }) else {
                return false
            }
            return functionKinds.contains(kind) && subkind == wanted

        case .topLevelCode:
            return false
        }
    }
}
