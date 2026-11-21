//
//  CoverageAttachment.swift
//  SwiftStatsCore
//
//  Coverage outside every function record (M5, PRD §6.1): stored-property
//  and property-wrapper initialisers, lazy getters and global closures,
//  attached to the innermost type holding them, else to their file.
//

/// Coverage attached to a type or a file.
public struct CoverageAttachment: Codable, Hashable, Sendable {
    /// The type as `TypeOwner` names it (`<module>::<type path>`, with
    /// ` @ <file>` for a file-scoped type), or the file's path.
    public let owner: String
    /// `type` or `file`.
    public let attachedTo: FindingTarget
    /// The mapped lines in no record's line span that the owner holds,
    /// by llvm-cov's file line rule.
    public let lines: CoverageTally
    /// The code regions of the entries attached to the owner, deduplicated
    /// by range with the largest count.
    public let regions: CoverageTally

    /// Creates an attachment. Fields are documented on their properties.
    public init(owner: String, attachedTo: FindingTarget, lines: CoverageTally, regions: CoverageTally) {
        self.owner = owner
        self.attachedTo = attachedTo
        self.lines = lines
        self.regions = regions
    }
}
