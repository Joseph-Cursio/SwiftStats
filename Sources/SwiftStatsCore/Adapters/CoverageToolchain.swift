//
//  CoverageToolchain.swift
//  SwiftStatsCore
//
//  The toolchain a coverage run uses (M5): the `SwiftToolchain` the
//  resolved `swift` selects, whose own `swift` runs every command, plus
//  `llvm-profdata` and `llvm-cov`, from beside that `swift` when both are
//  there, else from `xcrun --find`. Tool paths are never recorded.
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

    /// The toolchain the resolved `swift` selects.
    let base: SwiftToolchain
    /// `llvm-profdata`.
    let profdata: URL
    /// `llvm-cov`.
    let cov: URL
    /// `toolchainSource` or `xcrunSource`.
    let source: String
    /// `llvm-profdata`'s version line (`versionLine(of:)`).
    let profdataVersion: String
    /// `llvm-cov`'s version line.
    let covVersion: String

    /// The toolchain's own `swift`.
    var swift: URL {
        base.swift
    }

    /// The toolchain's directory, the part of a tool's path a reason
    /// redacts.
    var directory: URL {
        base.directory
    }

    /// The first non-empty line `swift --version` prints, trimmed.
    var swiftVersion: String {
        base.swiftVersion
    }

    /// The options that record the tools: where they came from and their
    /// versions.
    var options: [String] {
        ["llvm tools: \(source)", "llvm-profdata: \(profdataVersion)", "llvm-cov: \(covVersion)"]
    }

    /// The toolchain `swift` resolves to for the package `command` runs
    /// in; `xcrun` is looked up with `locator` when the toolchain lacks the
    /// LLVM tools.
    static func discover(swift resolved: URL, command: CoverageCommand, locator: ToolLocator) throws -> Self {
        // The LLVM tools are found before the toolchain's own `swift` is
        // asked for its version, so a missing `xcrun` is reported first.
        let located = try SwiftToolchain.locate(swift: resolved, command: command)
        let bin = located.swift.deletingLastPathComponent()
        let beside = ["llvm-profdata", "llvm-cov"].map { bin.appendingPathComponent($0) }
        let inToolchain = beside.allSatisfy { FileManager.default.isExecutableFile(atPath: $0.path) }
        let llvm = inToolchain ? beside : try xcrunTools(command: command, locator: locator)
        let selected = try SwiftToolchain(
            swift: located.swift,
            runtimeResources: located.runtimeResources,
            command: command
        )
        return Self(
            base: selected,
            profdata: llvm[0],
            cov: llvm[1],
            source: inToolchain ? toolchainSource : xcrunSource,
            profdataVersion: versionLine(of: try SwiftToolchain.version(of: llvm[0], command: command)),
            covVersion: versionLine(of: try SwiftToolchain.version(of: llvm[1], command: command))
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
        let path = SwiftToolchain.firstLine(of: String(bytes: output.output, encoding: .utf8) ?? "")
        guard path.isEmpty == false else {
            throw CoverageFailure(description: "`\(display)` printed no path")
        }
        return URL(fileURLWithPath: path)
    }
}
