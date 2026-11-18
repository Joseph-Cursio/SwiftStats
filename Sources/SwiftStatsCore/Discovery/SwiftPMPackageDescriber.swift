//
//  SwiftPMPackageDescriber.swift
//  SwiftStatsCore
//
//  The production describer: `swift package describe --type json`. It
//  evaluates the manifest but does not resolve or fetch dependencies, so a
//  T0 scan stays offline.
//

import Foundation

/// Describes a package by running `swift package describe --type json`.
public struct SwiftPMPackageDescriber: PackageDescriber {
    /// Creates a describer that uses the `swift` found on `PATH`.
    public init() {
        // Nothing to configure: the toolchain comes from `PATH` and any
        // `.swift-version` file in the package.
    }

    /// The package `output` describes; `packageRoot` names it in errors.
    static func decode(_ output: Data, packageRoot: URL) throws -> DescribedPackage {
        do {
            return try JSONDecoder().decode(DescribedPackage.self, from: output)
        } catch {
            throw ScanError.descriptionUnreadable(packageRoot.path, String(describing: error))
        }
    }

    /// Runs `swift package describe --type json` in `packageRoot` and
    /// decodes its output.
    public func describePackage(at packageRoot: URL) throws -> DescribedPackage {
        let output = try ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: ["swift", "package", "describe", "--type", "json"],
            in: packageRoot
        )
        return try Self.decode(output, packageRoot: packageRoot)
    }
}
