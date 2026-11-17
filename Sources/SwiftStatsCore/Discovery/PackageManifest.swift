//
//  PackageManifest.swift
//  SwiftStatsCore
//
//  The subset of `swift package dump-package` output SwiftStats needs: the
//  package name and, for each target, where its sources live. Everything else
//  in the manifest is ignored so new SwiftPM fields don't break decoding.
//

/// The parts of a package manifest that decide which files a scan covers.
public struct PackageManifest: Decodable, Sendable {
    /// The package name.
    public let name: String
    /// The package's targets, in manifest order.
    public let targets: [ManifestTarget]

    /// Creates a manifest. Fields are documented on their properties.
    public init(name: String, targets: [ManifestTarget]) {
        self.name = name
        self.targets = targets
    }
}
