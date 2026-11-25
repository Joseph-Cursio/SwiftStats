//
//  SwiftToolchain.swift
//  SwiftStatsCore
//
//  The toolchain a resolved `swift` stands for (M5, split out of
//  `CoverageToolchain` in M7). The resolved `swift` may be swiftly's proxy,
//  which picks a toolchain by the package's `.swift-version` and doesn't
//  pass signals on, so it is asked for `-print-target-info` in the package
//  root, and the `swift` beside the runtime resources it names
//  (`<runtimeResourcePath>/../../bin`) runs every later command. The
//  toolchain's `libIndexStore.dylib` sits beside those resources
//  (`<runtimeResourcePath>/../libIndexStore.dylib`). Tool paths are never
//  recorded.
//

import Foundation

/// The toolchain a resolved `swift` selects for one package.
struct SwiftToolchain: Sendable {
    /// The toolchain's own `swift`.
    let swift: URL
    /// The toolchain's directory (`<bin>/..`'s parent, the `usr`'s), the
    /// part of a tool's path a reason redacts.
    let directory: URL
    /// The runtime resources `-print-target-info` names,
    /// `<toolchain>/usr/lib/swift`, standardized.
    let runtimeResources: URL
    /// The first non-empty line `swift --version` prints, trimmed.
    let swiftVersion: String

    /// Where the toolchain's `libIndexStore.dylib` is, beside its runtime
    /// resources; whether it exists is the caller's question.
    var libIndexStore: URL {
        runtimeResources.deletingLastPathComponent().appendingPathComponent("libIndexStore.dylib")
    }

    /// The toolchain at `own`, its own `swift`, whose runtime resources
    /// are `resources`, with the version line `own --version` prints in
    /// the package `command` runs in.
    init(swift own: URL, runtimeResources resources: URL, command: CoverageCommand) throws {
        swift = own
        directory = own.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        runtimeResources = resources
        swiftVersion = Self.firstLine(of: try Self.version(of: own, command: command))
    }

    /// The toolchain `swift` resolves to for the package `command` runs in:
    /// its own `swift`, found beside the runtime resources the resolved
    /// one prints, and that `swift`'s version line.
    static func discover(swift resolved: URL, command: CoverageCommand) throws -> Self {
        let located = try locate(swift: resolved, command: command)
        return try Self(swift: located.swift, runtimeResources: located.runtimeResources, command: command)
    }

    /// The toolchain's own `swift`, beside the runtime resources the
    /// resolved one prints, and those resources, without running the own
    /// `swift`: a caller that looks for other tools first (coverage's
    /// `xcrun` lookup) does so before `init(swift:runtimeResources:command:)`
    /// asks for the version, so a missing tool is reported first.
    static func locate(swift resolved: URL, command: CoverageCommand) throws -> (swift: URL, runtimeResources: URL) {
        let resources = try runtimeResources(swift: resolved, command: command)
        // Standardizing a path with `..` resolves its symlinks, so only the
        // `bin` is: the toolchain's `swift` is a symlink to
        // `swift-frontend`, which acts as `swift` only by that name.
        let own = resources
            .appendingPathComponent("..")
            .appendingPathComponent("..")
            .appendingPathComponent("bin")
            .standardizedFileURL
            .appendingPathComponent("swift")
        guard FileManager.default.isExecutableFile(atPath: own.path) else {
            throw CoverageFailure(
                description: "`swift -print-target-info` names a toolchain with no `swift` beside its runtime resources"
            )
        }
        return (own, resources)
    }

    /// What `tool --version` prints, standard error when standard output
    /// is empty.
    static func version(of tool: URL, command: CoverageCommand) throws -> String {
        let output = try command.run(tool, ["--version"], display: "\(tool.lastPathComponent) --version")
        let text = String(bytes: output.output, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? output.errorText : text
    }

    /// The first non-empty line of `text`, trimmed; empty when there is none.
    static func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.isEmpty == false } ?? ""
    }

    /// The runtime resource path the resolved `swift` prints for
    /// `-print-target-info` in the package root, where swiftly's proxy
    /// reads the package's `.swift-version`, standardized.
    private static func runtimeResources(swift: URL, command: CoverageCommand) throws -> URL {
        let output = try command.run(swift, ["-print-target-info"], display: "swift -print-target-info")
        let json = try? JSONSerialization.jsonObject(with: output.output) as? [String: Any]
        guard let paths = json?["paths"] as? [String: Any],
              let resources = paths["runtimeResourcePath"] as? String else {
            throw CoverageFailure(description: "`swift -print-target-info` printed no paths.runtimeResourcePath")
        }
        return URL(fileURLWithPath: resources).standardizedFileURL
    }
}
