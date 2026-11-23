//
//  MutationDirectory.swift
//  SwiftStatsCore
//
//  Where the SwiftMutator collector keeps its files (M6, design §1.2):
//  `.swiftstats/mutation/` in the package, which `.swiftstats/`'s own
//  `.gitignore` of `*` keeps out of `git status`, whatever the store
//  setting. `work/` holds the temporary copy SwiftMutator runs in and
//  exists only while a run is under way, or after an interrupted one;
//  `build-cache/` holds the package's `.build` between runs, renamed into
//  and out of the copy, which the same volume makes cheap. `.lock` is held
//  for the whole mutation step, `muter.conf.yml` is the configuration
//  SwiftStats writes for each run (outside the copy, so SwiftMutator never
//  lists it), `swift-mutator.log` keeps the last step's output, and
//  `runs/<id>/` keeps each run's results file and report.
//

import Foundation

/// The mutation collector's folder in a package, and its parts.
struct MutationDirectory: Sendable {
    /// The folder's name inside `.swiftstats/`.
    static let name = "mutation"
    /// The temporary copy's folder's name.
    static let workName = "work"
    /// The kept build's folder's name.
    static let buildCacheName = "build-cache"
    /// The lock file's name.
    static let lockName = ".lock"
    /// The configuration's name, SwiftMutator's own.
    static let configurationName = "muter.conf.yml"
    /// The log's name.
    static let logName = "swift-mutator.log"
    /// The kept runs' folder's name.
    static let runsName = "runs"

    /// `.swiftstats/mutation/` in the package.
    let root: URL

    /// The folder the temporary copy is made in.
    var work: URL {
        root.appendingPathComponent(Self.workName)
    }

    /// The package's `.build` between runs.
    var buildCache: URL {
        root.appendingPathComponent(Self.buildCacheName)
    }

    /// The file locked while a mutation step runs.
    var lock: URL {
        root.appendingPathComponent(Self.lockName)
    }

    /// The configuration SwiftMutator is given.
    var configuration: URL {
        root.appendingPathComponent(Self.configurationName)
    }

    /// The output of the last step's commands.
    var log: URL {
        root.appendingPathComponent(Self.logName)
    }

    /// The folder of the runs kept.
    var runs: URL {
        root.appendingPathComponent(Self.runsName)
    }

    /// The folder of the package at `packageRoot`, made, with
    /// `.swiftstats/` and its `.gitignore`, when missing.
    init(packageRoot: URL) throws {
        root = try StoreLocation.ignoreDirectory(packageRoot: packageRoot).appendingPathComponent(Self.name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// The log of the package at `packageRoot`, made or not.
    static func log(packageRoot: URL) -> URL {
        packageRoot.standardizedFileURL
            .appendingPathComponent(StoreLocation.directoryName)
            .appendingPathComponent(name)
            .appendingPathComponent(logName)
    }
}
