//
//  CoverageArguments.swift
//  SwiftStatsCore
//
//  `collectors.coverage.arguments` (M5): what the coverage collector adds to
//  `swift test`. Only `--skip <regex>` pairs are allowed, since most other
//  `swift test` flags change or remove the profiles the collector reads
//  (`--disable-xctest`, `-c release`, `--filter`, `--parallel`, ...).
//  `collectors.swiftmutator.arguments` (M6) takes the same allowlist: the
//  pairs go into the test command of the configuration SwiftStats writes
//  for SwiftMutator.
//

import Yams

/// Checks the coverage and swiftmutator collectors' `swift test` arguments.
enum CoverageArguments {
    /// The one flag `arguments` may hold, each time followed by a regex.
    static let skipFlag = "--skip"
    /// The allowed form, as errors state it.
    static let allowedForm = "only `--skip <regex>` pairs are allowed"

    /// The arguments `value` lists for the collector `name`, or an error
    /// naming the first token that isn't part of a `--skip <regex>` pair.
    /// An absent or null value is no arguments.
    static func parse(_ value: Node?, name: String, path: String) throws -> [String] {
        guard let value, value.null == nil else {
            return []
        }
        let key = "collectors.\(name).arguments"
        guard let sequence = value.sequence else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a list of strings; \(allowedForm)")
        }
        let tokens = try sequence.map { item in
            // Yams gives a YAML null (`null`, `~`, nothing) as a scalar
            // whose text is that spelling, which would pass as a regex.
            guard item.null == nil, let token = item.scalar?.string else {
                throw ScanError.configurationInvalid(path, "`\(key)` must be a list of strings; \(allowedForm)")
            }
            return token
        }
        try check(tokens, key: key, path: path)
        return tokens
    }

    /// The regexes of the `--skip <regex>` pairs `arguments` holds, which
    /// `parse` has checked.
    static func skipPatterns(in arguments: [String]) -> [String] {
        zip(arguments, arguments.dropFirst()).compactMap { flag, pattern in
            flag == skipFlag ? pattern : nil
        }
    }

    /// Throws unless `tokens` are `--skip <regex>` pairs; `key` and `path`
    /// name the setting in the error.
    private static func check(_ tokens: [String], key: String, path: String) throws {
        var index = tokens.startIndex
        while index < tokens.endIndex {
            guard tokens[index] == skipFlag else {
                throw ScanError.configurationInvalid(
                    path,
                    "`\(key)`: `\(tokens[index])` is not allowed; \(allowedForm)"
                )
            }
            let regexIndex = tokens.index(after: index)
            guard regexIndex < tokens.endIndex else {
                throw ScanError.configurationInvalid(path, "`\(key)`: `\(skipFlag)` needs a regex after it")
            }
            // `swift test` would read a regex starting with `-` as another
            // flag, which would get past the allowlist.
            guard tokens[regexIndex].isEmpty == false, tokens[regexIndex].hasPrefix("-") == false else {
                throw ScanError.configurationInvalid(
                    path,
                    "`\(key)`: `\(tokens[regexIndex])` is not a regex for `\(skipFlag)`; \(allowedForm)"
                )
            }
            index = tokens.index(after: regexIndex)
        }
    }
}
