//
//  ManifestLoader.swift
//  SwiftStatsCore
//
//  Reads a package manifest by asking SwiftPM to evaluate it. `Package.swift`
//  is Swift code, so only SwiftPM can say what it declares; parsing it by hand
//  would miss computed target lists.
//

import Foundation

/// Loads the manifest of the package at a directory.
public protocol ManifestLoader: Sendable {
    /// Returns the manifest of the package rooted at `packageRoot`.
    func loadManifest(at packageRoot: URL) throws -> PackageManifest
}
