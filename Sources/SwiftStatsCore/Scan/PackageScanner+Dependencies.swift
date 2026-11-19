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
        /// The `swift` that was run; nil when the collector was skipped.
        let executable: URL?
        /// Wall-clock milliseconds.
        let milliseconds: Int
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
        let ((status, graph), milliseconds) = Stopwatch.time {
            DependencyGraphAdapter.run(swift: swift, root: root, direct: package.dependencies)
        }
        var executable: URL?
        if case .found(let found) = swift, status.state != .skipped {
            executable = found
        }
        let report = DependencyReport(
            direct: package.dependencies.sorted { $0.identity < $1.identity },
            lockfile: lockfile,
            resolved: graph
        )
        return DependencyScan(
            report: report,
            status: status,
            warnings: [lockfileWarning].compactMap(\.self),
            executable: executable,
            milliseconds: milliseconds
        )
    }
}
