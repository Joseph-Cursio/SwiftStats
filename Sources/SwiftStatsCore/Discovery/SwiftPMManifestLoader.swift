//
//  SwiftPMManifestLoader.swift
//  SwiftStatsCore
//
//  The production manifest loader: asks SwiftPM to evaluate `Package.swift`.
//

import Foundation

/// Loads a manifest by running `swift package dump-package`.
public struct SwiftPMManifestLoader: ManifestLoader {
    /// Creates a loader that uses the `swift` found on `PATH`.
    public init() {
        // Nothing to configure: the toolchain comes from `PATH` and any
        // `.swift-version` file in the package.
    }

    /// Runs `swift package dump-package` in `packageRoot` and decodes its JSON.
    public func loadManifest(at packageRoot: URL) throws -> PackageManifest {
        let output = try ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: ["swift", "package", "dump-package"],
            in: packageRoot
        )
        do {
            return try JSONDecoder().decode(PackageManifest.self, from: output)
        } catch {
            throw ScanError.manifestUnreadable(packageRoot.path, String(describing: error))
        }
    }
}
