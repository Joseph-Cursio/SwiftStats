//
//  ToolchainReader.swift
//  SwiftStatsCore
//
//  Reads the toolchain in use for a package (PRD §6.2). A command that is
//  missing or fails leaves its field nil.
//

import Foundation

/// Reads `swift --version`, swiftly's selection and the SDK version.
enum ToolchainReader {
    /// The toolchain as seen from the package at `root`.
    static func read(packageRoot root: URL, tools: ToolLocator) -> Toolchain {
        let swiftly = tools.locate("swiftly").flatMap { firstLine(of: $0.path, ["use"], in: root) }
        return Toolchain(
            swiftVersion: tools.locate("swift").flatMap { firstLine(of: $0.path, ["--version"], in: root) },
            swiftlySelection: swiftly,
            sdkVersion: firstLine(of: "/usr/bin/xcrun", ["--show-sdk-version"], in: root)
        )
    }

    /// The first non-empty line `executable` prints, trimmed, or nil.
    private static func firstLine(of executable: String, _ arguments: [String], in root: URL) -> String? {
        guard let data = try? ProcessRunner.run(executable: executable, arguments: arguments, in: root),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.isEmpty == false }
    }
}
