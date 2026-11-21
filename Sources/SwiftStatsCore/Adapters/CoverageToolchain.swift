//
//  CoverageToolchain.swift
//  SwiftStatsCore
//
//  The toolchain a coverage run uses (M5). The resolved `swift` may be
//  swiftly's proxy, which picks a toolchain by the package's
//  `.swift-version` and doesn't pass signals on, so the run asks it for
//  `-print-target-info` in the package root and uses the `swift` beside the
//  runtime resources it names (`<runtimeResourcePath>/../../bin`) for
//  every command. `llvm-profdata` and `llvm-cov` come from there when both
//  are, else from `xcrun --find`. Tool paths are never recorded.
//

import Foundation

/// The tools of the toolchain a coverage run uses.
struct CoverageToolchain: Sendable {
    /// Where `llvm-profdata` and `llvm-cov` came from when the toolchain has
    /// them, as the `llvm tools:` option says it.
    static let toolchainSource = "toolchain"
    /// Where they came from otherwise.
    static let xcrunSource = "xcrun"
    /// What the version line of an LLVM tool contains.
    private static let llvmVersion = "LLVM version"

    /// The toolchain's own `swift`.
    let swift: URL
    /// The toolchain's directory (`<bin>/..`'s parent, the `usr`'s), the
    /// part of a tool's path a reason redacts.
    let directory: URL
    /// `llvm-profdata`.
    let profdata: URL
    /// `llvm-cov`.
    let cov: URL
    /// `toolchainSource` or `xcrunSource`.
    let source: String
    /// The first non-empty line `swift --version` prints, trimmed.
    let swiftVersion: String
    /// `llvm-profdata`'s version line (`versionLine(of:)`).
    let profdataVersion: String
    /// `llvm-cov`'s version line.
    let covVersion: String

    /// The options that record the tools: where they came from and their
    /// versions.
    var options: [String] {
        ["llvm tools: \(source)", "llvm-profdata: \(profdataVersion)", "llvm-cov: \(covVersion)"]
    }

    /// The toolchain `swift` resolves to for the package `command` runs
    /// in; `xcrun` is looked up with `locator` when the toolchain lacks the
    /// LLVM tools.
    static func discover(swift resolved: URL, command: CoverageCommand, locator: ToolLocator) throws -> Self {
        let bin = try binDirectory(swift: resolved, command: command)
        let own = bin.appendingPathComponent("swift")
        guard FileManager.default.isExecutableFile(atPath: own.path) else {
            throw CoverageFailure(
                description: "`swift -print-target-info` names a toolchain with no `swift` beside its runtime resources"
            )
        }
        let beside = ["llvm-profdata", "llvm-cov"].map { bin.appendingPathComponent($0) }
        let inToolchain = beside.allSatisfy { FileManager.default.isExecutableFile(atPath: $0.path) }
        let llvm = inToolchain ? beside : try xcrunTools(command: command, locator: locator)
        return Self(
            swift: own,
            directory: bin.deletingLastPathComponent().deletingLastPathComponent(),
            profdata: llvm[0],
            cov: llvm[1],
            source: inToolchain ? toolchainSource : xcrunSource,
            swiftVersion: firstLine(of: try version(of: own, command: command)),
            profdataVersion: versionLine(of: try version(of: llvm[0], command: command)),
            covVersion: versionLine(of: try version(of: llvm[1], command: command))
        )
    }

    /// The line of an LLVM tool's `--version` `text` that contains
    /// `LLVM version`, trimmed (swift.org's tools print `LLVM
    /// (http://llvm.org/):` first, Xcode's `Apple LLVM version …`); when no
    /// line does, the non-empty lines, trimmed and joined by `; `.
    static func versionLine(of text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
        return lines.first { $0.contains(llvmVersion) } ?? lines.joined(separator: "; ")
    }

    /// The toolchain's `bin`, from the runtime resource path the resolved
    /// `swift` prints for `-print-target-info` in the package root, where
    /// swiftly's proxy reads the package's `.swift-version`.
    private static func binDirectory(swift: URL, command: CoverageCommand) throws -> URL {
        let output = try command.run(swift, ["-print-target-info"], display: "swift -print-target-info")
        let json = try? JSONSerialization.jsonObject(with: output.output) as? [String: Any]
        guard let paths = json?["paths"] as? [String: Any],
              let resources = paths["runtimeResourcePath"] as? String else {
            throw CoverageFailure(description: "`swift -print-target-info` printed no paths.runtimeResourcePath")
        }
        return URL(fileURLWithPath: resources)
            .appendingPathComponent("..")
            .appendingPathComponent("..")
            .appendingPathComponent("bin")
            .standardizedFileURL
    }

    /// `llvm-profdata` and `llvm-cov`, in that order, as `xcrun --find`
    /// names them, `xcrun` found with `locator`.
    private static func xcrunTools(command: CoverageCommand, locator: ToolLocator) throws -> [URL] {
        guard let xcrun = locator.locate("xcrun") else {
            throw CoverageFailure(
                description: "the toolchain has no llvm-profdata and llvm-cov, and `xcrun` was not found on PATH"
            )
        }
        return try ["llvm-profdata", "llvm-cov"].map { try find($0, xcrun: xcrun, command: command) }
    }

    /// The tool `name` that `xcrun --find` names.
    private static func find(_ name: String, xcrun: URL, command: CoverageCommand) throws -> URL {
        let display = "xcrun --find \(name)"
        let output = try command.run(xcrun, ["--find", name], display: display)
        let path = firstLine(of: String(bytes: output.output, encoding: .utf8) ?? "")
        guard path.isEmpty == false else {
            throw CoverageFailure(description: "`\(display)` printed no path")
        }
        return URL(fileURLWithPath: path)
    }

    /// What `tool --version` prints, standard error when standard output
    /// is empty.
    private static func version(of tool: URL, command: CoverageCommand) throws -> String {
        let output = try command.run(tool, ["--version"], display: "\(tool.lastPathComponent) --version")
        let text = String(bytes: output.output, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? output.errorText : text
    }

    /// The first non-empty line of `text`, trimmed; empty when there is none.
    private static func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.isEmpty == false } ?? ""
    }
}
