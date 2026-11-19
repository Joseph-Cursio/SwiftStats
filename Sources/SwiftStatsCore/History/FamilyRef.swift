//
//  FamilyRef.swift
//  SwiftStatsCore
//
//  A family as history follows it: its key and its file.
//

/// A family as history follows it: its key and file.
struct FamilyRef: Hashable, Sendable {
    /// The family's id (its root's key, or a property's key).
    let id: String
    /// The family's file.
    let file: String

    /// The ref of `family`.
    init(_ family: FunctionFamily) {
        id = family.id
        file = family.file
    }

    /// A ref. Fields are documented on their properties.
    init(id: String, file: String) {
        self.id = id
        self.file = file
    }
}
