//
//  ManifestTarget.swift
//  SwiftStatsCore
//
//  One target from `swift package dump-package`, reduced to where its sources
//  live.
//

/// One target as `Package.swift` declares it.
public struct ManifestTarget: Decodable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case exclude, name, path, sources, type
    }

    /// The target name.
    public let name: String
    /// The target type: `regular`, `executable`, `test`, `macro`,
    /// `plugin`, `system` or `binary`.
    public let type: String
    /// A custom source directory, relative to the package root.
    public let path: String?
    /// An explicit source list, relative to the target directory. Empty
    /// means the whole directory, as when `Package.swift` gives none.
    public let sources: [String]
    /// Paths to leave out, relative to the target directory.
    public let exclude: [String]

    /// Creates a target. Fields are documented on their properties.
    public init(name: String, type: String, path: String?, sources: [String], exclude: [String]) {
        self.name = name
        self.type = type
        self.path = path
        self.sources = sources
        self.exclude = exclude
    }

    /// Decodes a target, treating a missing `sources` or `exclude` as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        exclude = try container.decodeIfPresent([String].self, forKey: .exclude) ?? []
    }
}
