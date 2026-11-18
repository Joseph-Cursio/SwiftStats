//
//  DescribedPackage.swift
//  SwiftStatsCore
//
//  The subset of `swift package describe --type json` SwiftStats needs.
//  Everything else is ignored so new SwiftPM fields don't break decoding.
//

/// A package as SwiftPM describes it.
public struct DescribedPackage: Decodable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case dependencies, name, targets
    }

    /// The package name.
    public let name: String
    /// The package's targets.
    public let targets: [DescribedTarget]
    /// The package dependencies `Package.swift` declares.
    public let dependencies: [DescribedDependency]

    /// Creates a package description. Fields are documented on their
    /// properties.
    public init(name: String, targets: [DescribedTarget], dependencies: [DescribedDependency] = []) {
        self.name = name
        self.targets = targets
        self.dependencies = dependencies
    }

    /// Decodes SwiftPM's form; a package with no dependencies may omit them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        targets = try container.decode([DescribedTarget].self, forKey: .targets)
        dependencies = try container.decodeIfPresent([DescribedDependency].self, forKey: .dependencies) ?? []
    }
}
