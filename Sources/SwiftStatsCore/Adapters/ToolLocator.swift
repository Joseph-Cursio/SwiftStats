//
//  ToolLocator.swift
//  SwiftStatsCore
//
//  Finds the external tools the adapters run (PRD §7.16): a path from
//  `collectors.<name>.path` wins, otherwise the tool is looked up on PATH.
//

import Foundation

/// Finds a tool's executable by name.
public struct ToolLocator: Sendable {
    /// Looks tools up on the `PATH` of this process.
    public static let path = Self { name in
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return directories
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Finds no tool, so every adapter is skipped; for scans that must not
    /// depend on what is installed.
    public static let nowhere = Self { _ in nil }

    /// The executable called `name`, or nil.
    private let lookUp: @Sendable (String) -> URL?

    /// A locator that asks `lookUp` for each name.
    @preconcurrency
    public init(_ lookUp: @escaping @Sendable (String) -> URL?) {
        self.lookUp = lookUp
    }

    /// The executable called `name`, or nil when there is none.
    public func locate(_ name: String) -> URL? {
        lookUp(name)
    }
}
