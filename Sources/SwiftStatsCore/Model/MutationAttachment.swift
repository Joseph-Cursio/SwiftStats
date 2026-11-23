//
//  MutationAttachment.swift
//  SwiftStatsCore
//
//  Mutants outside every function record (M6, design §3): stored-property
//  initial values attached to the innermost type holding them, global
//  initialisers and `main.swift`'s eager globals off its statement lines
//  attached to their file; counted by verdict.
//

/// Mutants attached to a type or a file, counted.
public struct MutationAttachment: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes beside the counts.
    private enum CodingKeys: String, CodingKey {
        case owner
        case attachedTo
    }

    /// The type as `TypeOwner` names it, or the file's path.
    public let owner: String
    /// `type` or `file`.
    public let attachedTo: FindingTarget
    /// Its mutants by verdict.
    public let counts: MutationCounts

    /// Creates an attachment. Fields are documented on their properties.
    public init(owner: String, attachedTo: FindingTarget, counts: MutationCounts) {
        self.owner = owner
        self.attachedTo = attachedTo
        self.counts = counts
    }

    /// Reads the attachment, its counts beside its fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(String.self, forKey: .owner)
        attachedTo = try container.decode(FindingTarget.self, forKey: .attachedTo)
        counts = try MutationCounts(from: decoder)
    }

    /// Writes the attachment, its counts beside its fields.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(owner, forKey: .owner)
        try container.encode(attachedTo, forKey: .attachedTo)
        try counts.encode(to: encoder)
    }
}
