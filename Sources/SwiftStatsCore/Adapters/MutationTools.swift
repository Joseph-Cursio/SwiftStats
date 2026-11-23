//
//  MutationTools.swift
//  SwiftStatsCore
//
//  The SwiftMutator collector's two tools (M6, design §1.1): the
//  `swift-mutator` `collectors.swiftmutator` names, and the `swift` of its
//  test command, the coverage collector's. A scan resolves them before it
//  runs the collector, and `scan --mutation --resume` before anything
//  runs, to compare them with the run it continues.
//

import Foundation

/// The SwiftMutator collector's tools, or why it won't run.
enum MutationTools {
    /// Run `mutator`, whose tests run `swift`.
    case found(mutator: URL, swift: URL)
    /// Don't run; the reason says why.
    case skip(String)

    /// The tools for the package at `root` under `configuration`, found
    /// with `locator`: the `swift-mutator` first, then the test command's
    /// `swift`.
    static func resolve(root: URL, configuration: SwiftStatsConfiguration, locator: ToolLocator) -> Self {
        let mutator: URL
        switch ToolResolution.resolve(
            MutationAdapter.name,
            executable: MutationAdapter.executableName,
            configuration: configuration,
            locator: locator,
            root: root
        ) {
        case .found(let found):
            mutator = found

        case .skip(let reason):
            return .skip(reason)
        }
        switch MutationAdapter.testSwift(configuration: configuration, locator: locator, root: root) {
        case .found(let swift):
            return .found(mutator: mutator, swift: swift)

        case .skip(let reason):
            return .skip(reason)
        }
    }
}
