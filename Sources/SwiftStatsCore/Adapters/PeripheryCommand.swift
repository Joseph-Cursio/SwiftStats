//
//  PeripheryCommand.swift
//  SwiftStatsCore
//
//  outskirts' two command lines (M7, design §5.2), each flag its own
//  argument: the JSON format, no update check (otherwise a scan calls
//  GitHub), an empty configuration file of SwiftStats' own (a package's
//  `.outskirts.yml` would change the results), the T1 build's index store
//  with the build skipped, everything under the build directory excluded
//  by its absolute real path (outskirts' default exclude doesn't match
//  `.swiftstats/index-build`), the T1 describe as the package manifest
//  (otherwise outskirts describes the package itself, leaving `.build` in
//  its root), the library-product modules and the package modules they
//  re-export (`@_exported import`, transitively) whose public
//  declarations are retained, by C99 name and only when there are any,
//  synthesized Codable
//  and Equatable properties retained, and, for the `production` run,
//  tests left out of the roots. The options give both command lines with
//  the build directory, the describe and the configuration as
//  placeholders, and the retained modules by target name, followed by the
//  rule that chose them.
//

import Foundation

/// outskirts' command lines and the files they read and write.
enum PeripheryCommand {
    /// One of the two runs, as the dead-code results name it.
    typealias Run = DeadCodeRun

    /// The configuration file outskirts reads, empty, in the build
    /// directory.
    static let configurationName = "swiftstats-outskirts.yml"
    /// What an option's command line says for the build directory.
    static let buildPlaceholder = "<build>"
    /// What it says for the T1 describe.
    static let describePlaceholder = "<describe>"
    /// What it says for the configuration file.
    static let configurationPlaceholder = "<config>"
    /// What the option naming the retained modules starts with.
    static let retainOptionLead = "retain-public-modules: "
    /// What that option says when no module is retained.
    static let noneRetained = "none"
    /// The rule choosing the retained modules, as that option states it
    /// after them.
    static let retainRule = "(the targets library products list and the package targets they re-export with "
        + "@_exported import, transitively, each with a kept or variant unit)"
    /// The flag that leaves tests out of the roots.
    private static let excludeTests = "--exclude-tests"
    /// The flag naming the retained modules, followed by each of them.
    private static let retainPublicModules = "--retain-public-modules"

    /// The file `run`'s standard output is kept in, in the build directory.
    static func outputName(_ run: Run) -> String {
        "swiftstats-outskirts-\(run.rawValue).json"
    }

    /// The arguments of `run` after the executable, over the build
    /// directory at `scratch` (its real path), with the T1 describe at
    /// `describe`, the configuration file at `configuration`, retaining
    /// the public declarations of `retained`, C99 module names in byte
    /// order.
    static func arguments(
        _ run: Run,
        scratch: String,
        describe: String,
        configuration: String,
        retained: [String]
    ) -> [String] {
        ["scan", "--format", "json", "--disable-update-check", "--config", configuration]
            + ["--index-store-path", scratch + "/" + BuildSession.storeDirectory, "--skip-build"]
            + ["--index-exclude", scratch + "/**"]
            + ["--json-package-manifest-path", describe]
            + (retained.isEmpty ? [] : [retainPublicModules] + retained)
            + ["--retain-codable-properties", "--retain-equatable-properties"]
            + (run == .production ? [excludeTests] : [])
    }

    /// `run`'s command line as the options give it: `<run>: outskirts`
    /// and its arguments, with the build directory, the describe and the
    /// configuration file as placeholders.
    static func option(_ run: Run, retained: [String]) -> String {
        let words = arguments(
            run,
            scratch: buildPlaceholder,
            describe: describePlaceholder,
            configuration: configurationPlaceholder,
            retained: retained
        )
        return "\(run.rawValue): \(PeripheryAdapter.executableName) " + words.joined(separator: " ")
    }

    /// The option naming the retained modules by target name, `targets`
    /// in code point order, or `none`, then the rule choosing them.
    static func retainOption(targets: [String]) -> String {
        retainOptionLead
            + (targets.isEmpty ? noneRetained : targets.sorted(by: CodePointOrder.precedes).joined(separator: ", "))
            + " " + retainRule
    }
}
