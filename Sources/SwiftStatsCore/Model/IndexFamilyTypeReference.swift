//
//  IndexFamilyTypeReference.swift
//  SwiftStatsCore
//
//  A production family's reference to a type of the package, or to a
//  member of it (owning type as design §4.3 finds it), from the T1 build's
//  index (M7, design §4.4, for hidden coupling).
//

/// One family's reference to a package type.
public struct IndexFamilyTypeReference: Codable, Hashable, Sendable {
    /// The referring family, as `FunctionFamily` names it.
    public let family: String
    /// The type's target.
    public let module: String
    /// The type's path.
    public let typePath: String
    /// The type's file when it is `private` or `fileprivate`; nil
    /// otherwise.
    public let typeFile: String?

    /// Creates the reference. Fields are documented on their properties.
    public init(family: String, module: String, typePath: String, typeFile: String?) {
        self.family = family
        self.module = module
        self.typePath = typePath
        self.typeFile = typeFile
    }
}
