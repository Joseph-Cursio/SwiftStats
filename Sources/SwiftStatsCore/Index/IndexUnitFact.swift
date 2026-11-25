//
//  IndexUnitFact.swift
//  SwiftStatsCore
//
//  One unit of an index store as an `IndexStoreSource` gives it (M7,
//  design §2.2): a compile of one main file for one module and target
//  triple, the records it wrote and the modules the file imports (its
//  dependencies of kind `unit`; there is no "module" kind). Values are as
//  the store holds them: the module is a C99 module name, the main file an
//  absolute real path in NFC ("" when the unit has none). Its coding keys
//  are those of `Scripts/index-check.py dump`, whose recordings
//  `RecordedIndexSource` decodes.
//

/// One unit of an index store, copied out of the reader.
struct IndexUnitFact: Decodable, Hashable, Sendable {
    /// A unit file's modification date at full precision.
    struct ModificationDate: Comparable, Decodable, Hashable, Sendable {
        /// Whole seconds since 1970.
        let seconds: Int64
        /// Nanoseconds past `seconds`.
        let nanoseconds: Int64

        /// Whether `lhs` is earlier than `rhs`.
        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.seconds, lhs.nanoseconds) < (rhs.seconds, rhs.nanoseconds)
        }
    }

    /// One of the unit's dependencies of kind `unit`: a module its main
    /// file imports.
    struct ModuleDependency: Decodable, Hashable, Sendable {
        /// The module's name as stored: a C99 module name.
        let module: String
        /// Whether the module is a system module (the SDK's, the
        /// toolchain's).
        let isSystem: Bool
    }

    /// The unit's name, its file name in `v5/units`.
    let name: String
    /// The module the unit was compiled for, as a C99 module name.
    let module: String
    /// The main file's absolute real path in NFC; "" when the unit has
    /// none (a clang module unit).
    let mainFile: String
    /// The target triple, such as `arm64-apple-macos14.0`.
    let target: String
    /// Whether the unit is a system unit (an SDK `.swiftinterface`).
    let isSystem: Bool
    /// The unit file's modification date.
    let modified: ModificationDate
    /// The names of the records the unit wrote (its dependencies of kind
    /// `record`), sorted.
    let records: [String]
    /// Its dependencies of kind `unit`, duplicates kept, as read.
    let moduleDependencies: [ModuleDependency]
}
