//
//  ToolResolution.swift
//  SwiftStatsCore
//
//  Whether a collector runs, and with which executable (PRD §7.16).
//

import Foundation

/// A collector's executable, or why it won't run.
enum ToolResolution {
    /// Run this executable.
    case found(URL)
    /// Don't run; the reason says why.
    case skip(String)

    /// How collector `name`, whose tool is called `executable` on PATH,
    /// resolves under `configuration`. A configured path is relative to `root`.
    static func resolve(
        _ name: String,
        executable: String,
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator,
        root: URL
    ) -> Self {
        resolve(name, executable: executable, settings: configuration.collectors[name], locator: locator, root: root)
    }

    /// How collector `name`, whose tool is called `executable` on PATH,
    /// resolves under its `settings` (nil when `.swiftstats.yml` has none).
    /// A configured path is relative to `root`.
    static func resolve(
        _ name: String,
        executable: String,
        settings: CollectorSettings?,
        locator: ToolLocator,
        root: URL
    ) -> Self {
        if settings?.enabled == false {
            return .skip("disabled by collectors.\(name).enabled")
        }
        if let path = settings?.path {
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                return .skip("collectors.\(name).path \(path) is not an executable file")
            }
            return .found(url)
        }
        guard let url = locator.locate(executable) else {
            return .skip("`\(executable)` not found on PATH; set collectors.\(name).path")
        }
        return .found(url)
    }
}
