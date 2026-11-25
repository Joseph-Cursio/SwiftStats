//
//  BuildAttachment.swift
//  SwiftStatsCore
//
//  Type-check time outside every record (M7, design §6.2): a stored
//  property's implicit accessors and initial value attached to the
//  innermost type holding them, a global's initialiser attached to its
//  file.
//

/// Type-check figures attached to a type or a file.
public struct BuildAttachment: Codable, Hashable, Sendable {
    /// The type as `TypeOwner` names it, or the file's path.
    public let owner: String
    /// `type` or `file`.
    public let attachedTo: FindingTarget
    /// The sum of its function-body entries, in whole milliseconds; nil
    /// when it has none (only expression entries).
    public let milliseconds: Int?
    /// Its largest expression entry, in whole milliseconds; nil when it has
    /// none.
    public let slowestExpression: Int?

    /// Creates the figures. Fields are documented on their properties.
    public init(owner: String, attachedTo: FindingTarget, milliseconds: Int?, slowestExpression: Int?) {
        self.owner = owner
        self.attachedTo = attachedTo
        self.milliseconds = milliseconds
        self.slowestExpression = slowestExpression
    }
}
