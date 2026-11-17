//
//  SitrepTypeFact.swift
//  SwiftStatsCore
//
//  What Sitrep records about one type it treats as top-level.
//

/// A type as Sitrep sees it.
struct SitrepTypeFact: Equatable {
    /// The declaration keyword: `class`, `enum`, `extension`, `protocol`,
    /// `struct`. Actors are invisible to Sitrep.
    let kind: String
    /// The type name; for an extension, the extended type as written.
    let name: String
    /// Inherited types as written, in order.
    let inheritance: [String]
    /// Non-empty lines of the declaration including its leading comments.
    let lineCount: Int
}
