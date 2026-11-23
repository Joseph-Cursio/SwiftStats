//
//  TreeDescriber.swift
//  SwiftStatsCoreTests
//
//  A describer that lists each target's Swift files as they are on disk
//  when it is asked, so a package whose files are renamed between scans
//  (a branch checked out, as the `--since` tests do) is described as
//  SwiftPM would describe it, with no SwiftPM.
//

import Foundation
@testable import SwiftStatsCore

/// A describer that reads its targets' sources from the package's tree.
struct TreeDescriber: PackageDescriber {
    /// The package's name.
    let name: String
    /// The targets, whose sources are ignored and read from disk instead.
    let targets: [DescribedTarget]

    /// The Swift files below `folder`, by their paths from it, sorted.
    private static func swiftFiles(in folder: URL) -> [String] {
        let entries = FileManager.default.enumerator(atPath: folder.path)?.allObjects as? [String] ?? []
        return entries.filter { $0.hasSuffix(".swift") }.sorted()
    }

    func describePackage(at root: URL) -> DescribedPackage {
        DescribedPackage(
            name: name,
            targets: targets.map { target in
                DescribedTarget(
                    name: target.name,
                    type: target.type,
                    moduleType: target.moduleType,
                    path: target.path,
                    sources: Self.swiftFiles(in: root.appendingPathComponent(target.path)),
                    targetDependencies: target.targetDependencies
                )
            }
        )
    }
}
