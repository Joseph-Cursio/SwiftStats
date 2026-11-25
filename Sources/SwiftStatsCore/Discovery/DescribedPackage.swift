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
        case dependencies, name, products, targets
    }

    /// The package name.
    public let name: String
    /// The package's targets.
    public let targets: [DescribedTarget]
    /// The package dependencies `Package.swift` declares.
    public let dependencies: [DescribedDependency]
    /// The products `Package.swift` declares, in its order.
    public let products: [DescribedProduct]

    /// Creates a package description. Fields are documented on their
    /// properties.
    public init(
        name: String,
        targets: [DescribedTarget],
        dependencies: [DescribedDependency] = [],
        products: [DescribedProduct] = []
    ) {
        self.name = name
        self.targets = targets
        self.dependencies = dependencies
        self.products = products
    }

    /// Decodes SwiftPM's form; a package with no dependencies or products
    /// may omit them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        targets = try container.decode([DescribedTarget].self, forKey: .targets)
        dependencies = try container.decodeIfPresent([DescribedDependency].self, forKey: .dependencies) ?? []
        products = try container.decodeIfPresent([DescribedProduct].self, forKey: .products) ?? []
    }
}
