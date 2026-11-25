//
//  DeadCodeVia.swift
//  SwiftStatsCore
//
//  How an outskirts entry covers a record (M7, design §5.4), the first
//  rule that applies: by USR, a property's accessor records, a type's
//  records in any file, an extension's records in its range, or a
//  function by its name position when the index didn't run.
//

/// The rule by which an outskirts entry covers a record.
public enum DeadCodeVia: String, Codable, CaseIterable, Sendable {
    /// An extension entry: the records in the extension's range.
    case extensionDeclaration = "extension"
    /// A function entry by its name position (the index didn't run).
    case location
    /// A variable entry: its property's accessor records.
    case property
    /// A nominal type entry: every record the type, or a type nested in
    /// it, owns.
    case type
    /// An id of the entry is the record's primary or secondary USR.
    case usr
}
