//
//  GlobPattern.swift
//  SwiftStatsCore
//
//  Path globs for `.swiftstats.yml` (PRD §10.1), matched against paths
//  relative to the package root: `*` and `?` stay within one path component,
//  `**` spans any number of them, and a pattern with no wildcard also
//  matches everything under it, so `Sources/Generated` excludes that folder.
//

import Foundation

/// A path glob.
struct GlobPattern: Hashable {
    /// The prefix a pattern may start with, meaning the package root.
    private static let rootPrefix = "./"

    /// The pattern as written, without a leading `./` or trailing `/`.
    let pattern: String
    /// The pattern as an anchored regular expression.
    private let expression: NSRegularExpression?

    /// A glob for `pattern`.
    init(_ pattern: String) {
        var trimmed = pattern
        if trimmed.hasPrefix(Self.rootPrefix) {
            trimmed.removeFirst(Self.rootPrefix.count)
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        self.pattern = trimmed
        expression = try? NSRegularExpression(pattern: "^" + Self.regex(for: trimmed) + "(/.*)?$")
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pattern == rhs.pattern
    }

    /// The regular expression for a glob, without anchors.
    private static func regex(for glob: String) -> String {
        var result = ""
        var characters = Array(glob)[...]
        while let character = characters.popFirst() {
            switch character {
            case "*" where characters.first == "*":
                characters.removeFirst()
                if characters.first == "/" {
                    characters.removeFirst()
                    result += "(.*/)?"
                } else {
                    result += ".*"
                }

            case "*":
                result += "[^/]*"

            case "?":
                result += "[^/]"

            default:
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return result
    }

    /// Whether the glob matches `path`, or a folder that contains it.
    func matches(_ path: String) -> Bool {
        guard let expression else {
            return false
        }
        let range = NSRange(path.startIndex..., in: path)
        return expression.firstMatch(in: path, range: range) != nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pattern)
    }
}
