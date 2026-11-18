//
//  DescribedTarget.swift
//  SwiftStatsCore
//
//  One target from `swift package describe --type json`: where it lives and
//  the source files SwiftPM compiles for it, after SwiftPM has applied its own
//  rules (custom paths, `sources`, `exclude`, resources, symlinks, bundle
//  directories, default directory search).
//

/// A target as SwiftPM describes it.
public struct DescribedTarget: Decodable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case moduleType = "module_type"
        case name, path, sources, type
        case targetDependencies = "target_dependencies"
    }

    /// The target name, which is also its module name.
    public let name: String
    /// The target type: `library`, `executable`, `test`, `macro`, `plugin`,
    /// `system-target` or `binary`.
    public let type: String
    /// The module type: `SwiftTarget`, `ClangTarget`, `PluginTarget`, …
    public let moduleType: String
    /// The target directory, relative to the package root.
    public let path: String
    /// The compiled source files, relative to the target directory.
    public let sources: [String]
    /// The package's own targets this one depends on, by name.
    public let targetDependencies: [String]

    /// Creates a target. Fields are documented on their properties.
    public init(
        name: String,
        type: String,
        moduleType: String,
        path: String,
        sources: [String],
        targetDependencies: [String] = []
    ) {
        self.name = name
        self.type = type
        self.moduleType = moduleType
        self.path = path
        self.sources = sources
        self.targetDependencies = targetDependencies
    }

    /// Decodes a target; a target without sources (binary, system) gets none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        moduleType = try container.decodeIfPresent(String.self, forKey: .moduleType) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        targetDependencies = try container.decodeIfPresent([String].self, forKey: .targetDependencies) ?? []
    }
}
