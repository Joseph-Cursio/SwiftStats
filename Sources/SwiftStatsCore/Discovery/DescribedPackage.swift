//
//  DescribedPackage.swift
//  SwiftStatsCore
//
//  The subset of `swift package describe --type json` SwiftStats needs.
//  Everything else is ignored so new SwiftPM fields don't break decoding.
//

/// A package as SwiftPM describes it.
public struct DescribedPackage: Decodable, Sendable {
    /// The package name.
    public let name: String
    /// The package's targets.
    public let targets: [DescribedTarget]

    /// Creates a package description. Fields are documented on their
    /// properties.
    public init(name: String, targets: [DescribedTarget]) {
        self.name = name
        self.targets = targets
    }
}
