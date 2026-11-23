//
//  MutationPlace.swift
//  SwiftStatsCore
//
//  Where a mutant went in the mapping (M6, design §3): to a production
//  record, attached to a type or a file, unmapped in a production file the
//  mapping can't use, or dropped by design.
//

/// Where a mutant went.
public enum MutationPlace: String, Codable, CaseIterable, Sendable {
    /// Dropped by design: a build product, outside the root, a test file,
    /// another language's or another package's file.
    case dropped
    /// Attached to its file, outside every record and type.
    case file
    /// To the innermost production record holding its anchor.
    case record
    /// Attached to the innermost type holding its anchor, outside every
    /// record.
    case type
    /// In a production file, but not mapped, for a reason.
    case unmapped
}
