//
//  MutationConfigFile.swift
//  SwiftStatsCore
//
//  The `muter.conf.yml` SwiftStats writes for each SwiftMutator run (M6,
//  design §1.3), outside the copy, and passes with `-c`: the test command
//  is the resolved `swift`, by the absolute path it was found at (so
//  swiftly's proxy reads the copy's `.swift-version`), running `test` with
//  `collectors.swiftmutator.arguments` (allowlisted `--skip <regex>`
//  pairs) after it, and nothing excluded beyond SwiftMutator's defaults. A
//  package's own `muter.conf.yml` is never read. The file is the same for
//  the same settings, since `executable` and `arguments` are what
//  SwiftMutator compares for `--resume`. Every value is written as a
//  double-quoted scalar, JSON's escapes being YAML's, so no path or
//  regular expression can be misread.
//

import Foundation

/// The configuration SwiftStats gives SwiftMutator.
enum MutationConfigFile {
    /// The text of the configuration whose test command is `swift test`
    /// followed by `arguments`.
    static func text(swift: URL, arguments: [String]) -> String {
        var lines = ["executable: " + quoted(swift.path), "arguments:", "- " + quoted("test")]
        lines += arguments.map { "- " + quoted($0) }
        lines += ["exclude: []", "excludeCalls: []"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes that configuration to `file`, replacing any there.
    static func write(swift: URL, arguments: [String], to file: URL) throws(MutationFailure) {
        do {
            try Data(text(swift: swift, arguments: arguments).utf8).write(to: file, options: .atomic)
        } catch {
            throw MutationWorkCopy.failure("write .swiftstats/mutation/\(file.lastPathComponent)", error)
        }
    }

    /// `value` as a double-quoted YAML scalar.
    private static func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(value), let text = String(bytes: data, encoding: .utf8) else {
            return "\"\""
        }
        return text
    }
}
