//
//  DescribedDependency.swift
//  SwiftStatsCore
//
//  One direct dependency as `swift package describe --type json` gives it
//  (PRD §7.14).
//

/// A package dependency declared in `Package.swift`.
public struct DescribedDependency: Codable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case identity, location, path, requirement, type, url
    }

    /// The requirement's keys, as SwiftPM writes them.
    private enum RequirementKeys: String, CodingKey {
        case branch, exact, range, revision
    }

    /// SwiftPM's identity for the package.
    public let identity: String
    /// `sourceControl`, `fileSystem` or `registry`.
    public let type: String
    /// The URL, path or registry identity it comes from.
    public let location: String
    /// The version requirement (`1.0.0..<2.0.0`, `exact 1.2.3`, `branch
    /// main`, `revision <sha>`); nil for a local path.
    public let requirement: String?

    /// Creates a dependency. Fields are documented on their properties.
    public init(identity: String, type: String, location: String, requirement: String?) {
        self.identity = identity
        self.type = type
        self.location = location
        self.requirement = requirement
    }

    /// Decodes SwiftPM's form.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = try container.decode(String.self, forKey: .identity)
        type = try container.decode(String.self, forKey: .type)
        location = try container.decodeIfPresent(String.self, forKey: .url)
            ?? container.decodeIfPresent(String.self, forKey: .path)
            ?? container.decodeIfPresent(String.self, forKey: .location)
            ?? identity
        guard container.contains(.requirement) else {
            requirement = nil
            return
        }
        if let written = try? container.decode(String.self, forKey: .requirement) {
            requirement = written
            return
        }
        let values = try container.nestedContainer(keyedBy: RequirementKeys.self, forKey: .requirement)
        if let ranges = try values.decodeIfPresent([[String: String]].self, forKey: .range) {
            requirement = ranges.map { "\($0["lower_bound"] ?? "")..<\($0["upper_bound"] ?? "")" }
                .joined(separator: ", ")
        } else if let exact = try values.decodeIfPresent([String].self, forKey: .exact) {
            requirement = "exact " + exact.joined(separator: ", ")
        } else if let branch = try values.decodeIfPresent([String].self, forKey: .branch) {
            requirement = "branch " + branch.joined(separator: ", ")
        } else if let revision = try values.decodeIfPresent([String].self, forKey: .revision) {
            requirement = "revision " + revision.joined(separator: ", ")
        } else {
            requirement = nil
        }
    }

    /// Encodes SwiftStats' form: identity, type, location and requirement.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identity, forKey: .identity)
        try container.encode(type, forKey: .type)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(requirement, forKey: .requirement)
    }
}
