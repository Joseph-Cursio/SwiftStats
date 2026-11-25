//
//  ReferenceContainer.swift
//  SwiftStatsCore
//
//  What a reference occurrence is counted from (M7, design §4.1): a
//  record, a symbol that isn't one (a stored property's initializer, a
//  global, a Swift Testing peer), a type record holding the reference, or
//  the file, with the name a test referrer list shows, the target it is
//  in, and its owning package type.
//

/// The container of one reference.
struct ReferenceContainer {
    /// What tells one container from another.
    enum Identity: Hashable {
        /// A record, by key.
        case record(String)
        /// A symbol that isn't a record, by USR.
        case symbol(String)
        /// A type record holding the reference, by its identity.
        case type(TypeIdentity)
        /// The file, by path.
        case file(String)
    }

    /// The container.
    let identity: Identity
    /// Its name in a test referrer list: a record's key, a symbol's name,
    /// a type record's type path, or the file's path.
    let name: String
    /// Its target; nil when its file is no read unit's.
    let target: String?
    /// Its owning package type; nil when it has none.
    let owner: String?

    /// The record's key when the container is a record.
    var recordKey: String? {
        if case .record(let key) = identity {
            return key
        }
        return nil
    }
}
