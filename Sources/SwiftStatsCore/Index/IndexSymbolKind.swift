//
//  IndexSymbolKind.swift
//  SwiftStatsCore
//
//  Names for the raw symbol kinds, subkinds, properties and roles an index
//  store holds, for the ones SwiftStats reads (M7, design §2.2). Raw values
//  are stored as read (`IndexOccurrenceFact`); these constants are spelled
//  as indexstore-db's `IndexStore` at 64aa0b2 spells them
//  (`IndexStoreSymbol.swift`, `indexstore_functions.h`), with two
//  exceptions: the subkind `IndexStore` calls `none` is `plain` here
//  (SwiftLint's `discouraged_none_name`), and `swiftAccessorInit` (1016)
//  is SwiftStats' own: the C enum ends at 1015 with no init accessor, but
//  libIndexStore gives an `init` accessor raw subkind 1016 (probed: the
//  `init(initialValue)` accessor of `var x` defines `init:x`, kind
//  instance method, subkind 1016).
//

/// The symbol kinds SwiftStats reads, raw, with the subkinds, properties
/// and roles nested.
enum IndexSymbolKind {
    /// Symbol subkinds, raw.
    enum Subkind {
        /// No subkind (`IndexStore`'s `none`).
        static let plain = 0
        /// A getter.
        static let accessorGetter = 3
        /// A setter.
        static let accessorSetter = 4
        /// A `willSet` observer.
        static let swiftAccessorWillSet = 1_000
        /// A `didSet` observer.
        static let swiftAccessorDidSet = 1_001
        /// An `unsafeAddress` accessor.
        static let swiftAccessorAddressor = 1_002
        /// An `unsafeMutableAddress` accessor.
        static let swiftAccessorMutableAddressor = 1_003
        /// A prefix operator.
        static let swiftPrefixOperator = 1_008
        /// A postfix operator.
        static let swiftPostfixOperator = 1_009
        /// An infix operator.
        static let swiftInfixOperator = 1_010
        /// A subscript.
        static let swiftSubscript = 1_011
        /// A `_read` or `read` accessor (its symbol name is empty).
        static let swiftAccessorRead = 1_014
        /// A `_modify` or `modify` accessor.
        static let swiftAccessorModify = 1_015
        /// An `init` accessor: SwiftStats' own constant, past the C enum's
        /// end, for the raw subkind libIndexStore gives one.
        static let swiftAccessorInit = 1_016
    }

    /// Symbol property bits.
    enum Property {
        /// A unit test (an XCTest method or class).
        static let unitTest: UInt64 = 1 << 3
        /// A local symbol: a nested function, a local type or variable.
        static let local: UInt64 = 1 << 7
    }

    /// Occurrence role bits.
    enum Role {
        /// A declaration.
        static let declaration: UInt64 = 1 << 0
        /// A definition.
        static let definition: UInt64 = 1 << 1
        /// A reference.
        static let reference: UInt64 = 1 << 2
        /// A read.
        static let read: UInt64 = 1 << 3
        /// A write.
        static let write: UInt64 = 1 << 4
        /// A call.
        static let call: UInt64 = 1 << 5
        /// A dynamic dispatch.
        static let dynamic: UInt64 = 1 << 6
        /// An occurrence the compiler made, not the source.
        static let implicit: UInt64 = 1 << 8
    }

    /// Relation role bits, in the same bit space as `Role`.
    enum RelationRole {
        /// The symbol is a child of the related one.
        static let childOf: UInt64 = 1 << 9
        /// The symbol is a base of the related one.
        static let baseOf: UInt64 = 1 << 10
        /// The symbol overrides, or witnesses, the related one.
        static let overrideOf: UInt64 = 1 << 11
        /// The call is received by the related symbol.
        static let receivedBy: UInt64 = 1 << 12
        /// The occurrence is called by the related symbol.
        static let calledBy: UInt64 = 1 << 13
        /// The symbol is extended by the related extension.
        static let extendedBy: UInt64 = 1 << 14
        /// The symbol is an accessor of the related property or subscript.
        static let accessorOf: UInt64 = 1 << 15
        /// The occurrence is contained by the related symbol.
        static let containedBy: UInt64 = 1 << 16
    }

    /// An enum.
    static let `enum` = 5
    /// A struct.
    static let `struct` = 6
    /// A class.
    static let `class` = 7
    /// A protocol.
    static let `protocol` = 8
    /// An extension.
    static let `extension` = 9
    /// A typealias.
    static let `typealias` = 11
    /// A free or local function.
    static let function = 12
    /// A global or local variable.
    static let variable = 13
    /// An enum case.
    static let enumConstant = 15
    /// An instance method, accessors included.
    static let instanceMethod = 16
    /// A class method.
    static let classMethod = 17
    /// A static method.
    static let staticMethod = 18
    /// An instance property, subscripts included.
    static let instanceProperty = 19
    /// A class property.
    static let classProperty = 20
    /// A static property.
    static let staticProperty = 21
    /// An initializer.
    static let constructor = 22
    /// A deinitializer.
    static let destructor = 23
    /// A parameter.
    static let parameter = 25
}
