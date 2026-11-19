//
//  PackageOptions.swift
//  swiftstats
//
//  The options `scan`, `report` and `diff` share: which configuration file
//  and which store.
//

import ArgumentParser
import Foundation
import SwiftStatsCore

/// Which configuration and store a command uses.
struct PackageOptions: ParsableArguments {
    /// A configuration file to read instead of the package's own.
    @Option(help: "Read this configuration file instead of the package's .swiftstats.yml.")
    var config: String?

    /// A store to use instead of the configured or default one.
    @Option(help: "Use this snapshot store instead of store: in .swiftstats.yml or .swiftstats/stats.sqlite.")
    var store: String?

    /// The workspace of the package at `path` with these options.
    func workspace(path: String) throws -> SnapshotWorkspace {
        try SnapshotWorkspace(
            packageRoot: URL(fileURLWithPath: path, isDirectory: true),
            configurationFile: config.map { URL(fileURLWithPath: $0) },
            storeOverride: store,
            build: CurrentBuild.swiftStats,
            describer: SwiftPMPackageDescriber(),
            tools: .path
        )
    }
}
