//
//  CollectorRun.swift
//  SwiftStatsCore
//
//  Runs the external tools' collectors in a fixed order (PRD §7.16).
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

    /// `run`'s result, timed, when `resolution` found an executable, else a skip.
    private static func result(
        _ resolution: ToolResolution,
        name: String,
        run: (URL) -> AdapterResult
    ) -> TimedAdapterResult {
        switch resolution {
        case .found(let executable):
            let (result, milliseconds) = Stopwatch.time { run(executable) }
            return TimedAdapterResult(result: result, executable: executable, milliseconds: milliseconds)

        case .skip(let reason):
            return TimedAdapterResult(result: .skipped(name, reason: reason), executable: nil, milliseconds: 0)
        }
    }
}
