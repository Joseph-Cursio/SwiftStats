//
//  DescribedTarget.swift
//  SwiftStatsCore
//
//  One target from `swift package describe --type json`: where it lives and
//  the source files SwiftPM compiles for it, after SwiftPM has applied its own
//  rules (custom paths, `sources`, `exclude`, resources, symlinks, bundle
//  directories, default directory search), and its C99 module name, which
//  the index store and outskirts use where SwiftStats uses the target name
//  (M7, design choice 5).
//

/// A target as SwiftPM describes it.
public struct DescribedTarget: Decodable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case c99name
        case moduleType = "module_type"
        case name, path, sources, type
        case targetDependencies = "target_dependencies"
    }

    /// The target name, the module name SwiftStats stores.
    public let name: String
    /// The module name the compiler, the index store and outskirts use
    /// (`index-kit` → `index_kit`): SwiftPM's `c99name`, or, when the
    /// description has none, computed by SwiftPM's rule
    /// (`C99Identifier.moduleName(of:)`).
    public let c99name: String
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

    /// Creates a target. Fields are documented on their properties; a nil
    /// `c99name` is computed from `name`.
    public init(
        name: String,
        type: String,
        moduleType: String,
        path: String,
        sources: [String],
        targetDependencies: [String] = [],
        c99name: String? = nil
    ) {
        self.name = name
        self.c99name = c99name ?? C99Identifier.moduleName(of: name)
        self.type = type
        self.moduleType = moduleType
        self.path = path
        self.sources = sources
        self.targetDependencies = targetDependencies
    }

    /// Decodes a target; a target without sources (binary, system) gets
    /// none, and one without a `c99name` gets the computed one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        c99name = try container.decodeIfPresent(String.self, forKey: .c99name) ?? C99Identifier.moduleName(of: name)
        type = try container.decode(String.self, forKey: .type)
        moduleType = try container.decodeIfPresent(String.self, forKey: .moduleType) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        targetDependencies = try container.decodeIfPresent([String].self, forKey: .targetDependencies) ?? []
    }
}
