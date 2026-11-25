//
//  IndexTypeRow.swift
//  SwiftStatsCore
//
//  A production type of the package as the T1 build's index names it (M7,
//  design §4.3): a nominal type declared in the package, placed on the
//  scan's type record holding its definition, with its USR, its fan-in
//  (distinct referring types or free functions in its own target and in
//  other production targets, distinct test containers) and the number of
//  the USR type cycle it is in. Two local types of one name in one target
//  share `(module, typePath, typeFile)`: these rows still differ by USR,
//  but design §9.1's `typeIndex` key and `IndexFamilyTypeReference` don't
//  tell them apart (a design gap, open since step 5b).
//

/// One production type, its fan-in and its cycle.
public struct IndexTypeRow: Codable, Hashable, Sendable {
    /// Its target.
    public let module: String
    /// Its type path, as its type record names it.
    public let typePath: String
    /// Its file when it is `private` or `fileprivate`; nil otherwise.
    public let typeFile: String?
    /// Its USR.
    public let usr: String
    /// Distinct referring types, or free functions and other containers
    /// owned by no type, in its own target.
    public let referrersSameModule: Int
    /// The same, in other production targets.
    public let referrersOtherModules: Int
    /// Distinct test containers referring to it or its members.
    public let referrersTests: Int
    /// The number of its USR type cycle (1 the largest); nil when it is in
    /// none.
    public let cycle: Int?

    /// Creates the row. Fields are documented on their properties.
    public init(
        module: String,
        typePath: String,
        typeFile: String?,
        usr: String,
        referrersSameModule: Int,
        referrersOtherModules: Int,
        referrersTests: Int,
        cycle: Int?
    ) {
        self.module = module
        self.typePath = typePath
        self.typeFile = typeFile
        self.usr = usr
        self.referrersSameModule = referrersSameModule
        self.referrersOtherModules = referrersOtherModules
        self.referrersTests = referrersTests
        self.cycle = cycle
    }
}
