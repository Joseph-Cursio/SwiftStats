//
//  CollectorRun.swift
//  SwiftStatsCore
//
//  Runs the external tools' collectors in a fixed order (PRD §7.16), and
//  starts SwiftInferProperties' slower run (§7.11), SwiftCloneDetector's
//  runs (§7.12) and the coverage run (M5) in the background.
//

import Foundation

/// The external collectors.
enum CollectorRun {
    /// Runs every external collector on the package at `root`, whose
    /// scanned targets are `targets`.
    static func run(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator
    ) -> [TimedAdapterResult] {
        let lint = ToolResolution.resolve(
            SwiftProjectLintAdapter.name,
            executable: "swiftprojectlint",
            configuration: configuration,
            locator: locator,
            root: root
        )
        let swiftLint = ToolResolution.resolve(
            SwiftLintAdapter.name,
            executable: "swiftlint",
            configuration: configuration,
            locator: locator,
            root: root
        )
        return [
            result(lint, name: SwiftProjectLintAdapter.name) { executable in
                SwiftProjectLintAdapter.run(executable: executable, root: root)
            },
            result(swiftLint, name: SwiftLintAdapter.name) { executable in
                SwiftLintAdapter.run(executable: executable, root: root, targets: targets)
            }
        ]
    }

    /// Starts the SwiftInferProperties collector on the package at `root`,
    /// whose scanned targets are `targets`, on a background thread: it needs
    /// only the package's files, so it runs while the scan measures them.
    static func startProperties(
        root: URL,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator
    ) -> BackgroundJob<SwiftInferRun> {
        let resolution = ToolResolution.resolve(
            SwiftInferPropertiesAdapter.name,
            executable: SwiftInferPropertiesAdapter.executableName,
            configuration: configuration,
            locator: locator,
            root: root
        )
        return BackgroundJob {
            switch resolution {
            case .found(let executable):
                return SwiftInferPropertiesAdapter.run(executable: executable, root: root, targets: targets)

            case .skip(let reason):
                return SwiftInferRun.skipped(reason)
            }
        }
    }

    /// Starts the SwiftCloneDetector collector over `files` of the package
    /// at `root` on a background thread, so it runs beside SwiftProjectLint
    /// and SwiftLint.
    static func startClones(
        root: URL,
        files: [String],
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator
    ) -> BackgroundJob<CloneRun> {
        let resolution = ToolResolution.resolve(
            SwiftCloneDetectorAdapter.name,
            executable: SwiftCloneDetectorAdapter.executableName,
            configuration: configuration,
            locator: locator,
            root: root
        )
        return BackgroundJob {
            switch resolution {
            case .found(let executable):
                return SwiftCloneDetectorAdapter.run(executable: executable, root: root, files: files)

            case .skip(let reason):
                return CloneRun.skipped(reason)
            }
        }
    }

    /// Starts the coverage collector on the package at `root` on a
    /// background thread: it needs only the package's files to run, so it
    /// runs while the scan measures them. `collectors.coverage.path` names
    /// the `swift` whose toolchain it uses.
    static func startCoverage(
        root: URL,
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator
    ) -> BackgroundJob<CoverageRun> {
        let resolution = ToolResolution.resolve(
            CoverageAdapter.name,
            executable: "swift",
            configuration: configuration,
            locator: locator,
            root: root
        )
        let arguments = configuration.collectors[CoverageAdapter.name]?.arguments ?? []
        return BackgroundJob {
            switch resolution {
            case .found(let swift):
                return CoverageAdapter.run(swift: swift, root: root, arguments: arguments, locator: locator)

            case .skip(let reason):
                return CoverageRun.skipped(reason)
            }
        }
    }

    /// Every external collector skipped for `reason`.
    static func skipped(_ reason: String) -> [TimedAdapterResult] {
        [
            SwiftProjectLintAdapter.name, SwiftLintAdapter.name, SwiftInferPropertiesAdapter.name,
            SwiftCloneDetectorAdapter.name
        ].map { name in
            TimedAdapterResult(result: .skipped(name, reason: reason), executable: nil, identity: nil, milliseconds: 0)
        }
    }

    /// `run`'s result, timed, when `resolution` found an executable, else a skip.
    private static func result(
        _ resolution: ToolResolution,
        name: String,
        run: (URL) -> AdapterResult
    ) -> TimedAdapterResult {
        switch resolution {
        case .found(let executable):
            let (result, milliseconds) = Stopwatch.time { run(executable) }
            return TimedAdapterResult(
                result: result,
                executable: executable,
                identity: nil,
                milliseconds: milliseconds
            )

        case .skip(let reason):
            return TimedAdapterResult(
                result: .skipped(name, reason: reason),
                executable: nil,
                identity: nil,
                milliseconds: 0
            )
        }
    }
}
