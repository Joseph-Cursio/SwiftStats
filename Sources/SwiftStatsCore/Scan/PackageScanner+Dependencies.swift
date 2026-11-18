//
//  PackageScanner+Dependencies.swift
//  SwiftStatsCore
//
//  The dependency part of a scan (PRD §7.14).
//

import Foundation

extension PackageScanner {
    /// The dependency part of a scan.
    struct DependencyScan {
        /// Direct dependencies, pins and the resolved graph.
        let report: DependencyReport
        /// The `dependencies` collector's status.
        let status: CollectorStatus
        /// A warning when `Package.resolved` can't be read.
        let warnings: [ScanWarning]
    }

    /// The dependencies of `package`, at `root`.
    func dependencies(
        of package: DescribedPackage,
        root: URL,
        configuration: SwiftStatsConfiguration
    ) -> DependencyScan {
        let (lockfile, lockfileWarning) = PackageResolvedReader.lockfile(root: root)
        let swift = ToolResolution.resolve(
            DependencyGraphAdapter.name,
            executable: "swift",
            configuration: configuration,
            locator: tools,
            root: root
        )
        let (status, graph) = DependencyGraphAdapter.run(swift: swift, root: root, direct: package.dependencies)
        let report = DependencyReport(
            direct: package.dependencies.sorted { $0.identity < $1.identity },
            lockfile: lockfile,
            resolved: graph
        )
        return DependencyScan(report: report, status: status, warnings: [lockfileWarning].compactMap(\.self))
    }
}
