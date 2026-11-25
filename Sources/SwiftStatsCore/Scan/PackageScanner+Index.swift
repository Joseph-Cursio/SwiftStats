//
//  PackageScanner+Index.swift
//  SwiftStatsCore
//
//  The T1 group's part of a scan (M7, design §1.7): the `build`, `index`
//  and `periphery` collectors. They run only when the scan asks for them
//  (`scan --index`), alone, once SwiftInferProperties, the coverage run and
//  the clone detector have finished and before SwiftMutator, since the
//  type-check timings are wall-clock and nothing else may compete for the
//  CPU. Every scan lists the three statuses. Until the T1 session, the
//  reader and the outskirts collector are built, a requested group is
//  skipped with each collector's placeholder once its own settings let it
//  run (design §13).
//

import Foundation

extension PackageScanner {
    /// Why a requested build of the package at `root` is skipped:
    /// `collectors.build.enabled`, no coverage collector's `swift`
    /// (`MutationAdapter.testSwift`'s rule), else the placeholder.
    private static func buildSkipReason(
        root: URL,
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator
    ) -> String {
        if configuration.collectors[BuildAdapter.name]?.enabled == false {
            return "disabled by collectors.\(BuildAdapter.name).enabled"
        }
        let swift = MutationAdapter.testSwift(configuration: configuration, locator: locator, root: root)
        if case .skip(let reason) = swift {
            return reason
        }
        return BuildAdapter.notBuiltReason
    }

    /// Why a requested index read is skipped: `collectors.index.enabled`,
    /// else the placeholder, whatever the build did.
    private static func indexSkipReason(configuration: SwiftStatsConfiguration) -> String {
        if configuration.collectors[IndexAdapter.name]?.enabled == false {
            return "disabled by collectors.\(IndexAdapter.name).enabled"
        }
        return IndexAdapter.notBuiltReason
    }

    /// Why a requested outskirts run on the package at `root` is skipped:
    /// `collectors.periphery.enabled`, a path that isn't an executable or
    /// no `outskirts` on PATH, else the placeholder; outskirts never runs.
    private static func peripherySkipReason(
        root: URL,
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator
    ) -> String {
        let resolution = ToolResolution.resolve(
            PeripheryAdapter.name,
            executable: PeripheryAdapter.executableName,
            configuration: configuration,
            locator: locator,
            root: root
        )
        if case .skip(let reason) = resolution {
            return reason
        }
        return PeripheryAdapter.notBuiltReason
    }

    /// The T1 group's runs on the package at `root` under `configuration`,
    /// `build`, `index` and `periphery` in that order: skips when the scan
    /// didn't ask for them (`requested` false) or the tools are skipped,
    /// else each skipped for its own settings or its placeholder.
    func runIndexGroup(root: URL, configuration: SwiftStatsConfiguration, requested: Bool) -> [TimedAdapterResult] {
        let reasons: [(String, String)]
        if requested == false {
            reasons = [BuildAdapter.name, IndexAdapter.name, PeripheryAdapter.name].map { name in
                (name, BuildAdapter.notRequestedReason)
            }
        } else if let toolSkipReason {
            reasons = [BuildAdapter.name, IndexAdapter.name, PeripheryAdapter.name].map { name in
                (name, toolSkipReason)
            }
        } else {
            reasons = [
                (BuildAdapter.name, Self.buildSkipReason(root: root, configuration: configuration, locator: tools)),
                (IndexAdapter.name, Self.indexSkipReason(configuration: configuration)),
                (
                    PeripheryAdapter.name,
                    Self.peripherySkipReason(root: root, configuration: configuration, locator: tools)
                )
            ]
        }
        return reasons.map { name, reason in
            TimedAdapterResult(result: .skipped(name, reason: reason), executable: nil, identity: nil, milliseconds: 0)
        }
    }
}
