//
//  CoverageDemangler.swift
//  SwiftStatsCore
//
//  Demangles the names of unmapped coverage entries (M5) with the
//  toolchain's `swift demangle --compact`, a batch of names per call.
//

import Foundation

/// Demangles mangled names.
enum CoverageDemangler {
    /// How many names one call gets.
    private static let batchSize = 200

    /// Each of `names` demangled by `swift`, run in `root`; a batch whose
    /// output isn't one line per name is left out. Throws when a call
    /// fails.
    static func demangled(_ names: [String], swift: URL, root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        var start = 0
        while start < names.count {
            let batch = Array(names[start..<min(start + batchSize, names.count)])
            let output = try ProcessRunner.run(
                executable: swift.path,
                arguments: ["demangle", "--compact"] + batch,
                in: root
            )
            let lines = (String(bytes: output, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline)
            if lines.count == batch.count {
                for (name, line) in zip(batch, lines) {
                    result[name] = String(line)
                }
            }
            start += batchSize
        }
        return result
    }
}
