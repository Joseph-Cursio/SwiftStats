//
//  GlobRegex.swift
//  SwiftStatsCoreTests
//
//  The reference reading of a `.swiftstats.yml` glob, for the glob
//  differential: PRD §10.1's glob paragraph written as an ICU regular
//  expression, the form `GlobPattern` took before design B27 replaced it
//  with a direct matcher. One leading `./` and every trailing `/` are
//  dropped; the glob is read in Characters, two stars at a time, `**/`
//  becoming `(.*/)?`, any other `**` `.*`, `*` `[^/]*` and `?` `[^/]`, and
//  every other Character its escaped self; then `(/.*)?` lets every match
//  extend to the paths under it (decided U8), between `^` and `$`. ICU's
//  `.` stops at the line breaks §10.1 names and its `$` also matches before
//  one that ends the text, `\r\n` counting as one, which is §10.1's line
//  break rule. It leaves out B4's joining of star runs, which matched
//  exactly what the stars did one by one (step 13b's differential), so it
//  backtracks exponentially in the stars a failed match tries: the
//  reference is bounded only on globs of at most `starLimit` stars.
//

import Foundation

/// The reference reading of a glob, as an ICU regular expression.
enum GlobRegex {
    /// What the reference answers for a glob and a path.
    enum Answer: Equatable {
        /// The glob matches the path or a folder holding it.
        case matches
        /// It doesn't.
        case misses
        /// The glob's expression doesn't compile.
        case unreadable
    }

    /// The most `*` scalars a glob the reference reads may hold. Assumed:
    /// a failed match takes time growing with the path's length to the
    /// power of the stars, and four stars fail against paths as long as
    /// any `GlobGen` draws in a few milliseconds (`*a*a*a*ax` against 45 `a`s:
    /// 5.6 ms, the worst of step 13c's timings), where `*?` ten times took
    /// 13.7 s (design B27).
    static let starLimit = 4
    /// The prefix a glob may start with, meaning the package root.
    static let rootPrefix = "./"
    /// What lets every match extend to the paths under it, and anchors the
    /// end.
    static let folderSuffix = "(/.*)?$"

    /// Whether `glob` holds at most `starLimit` `*` scalars, so the
    /// reference reads it in bounded time.
    static func isBounded(_ glob: String) -> Bool {
        glob.unicodeScalars.count { $0 == "*" } <= starLimit
    }

    /// The regular expression for `glob`, anchored at both ends.
    static func expression(for glob: String) -> String {
        var trimmed = glob
        if trimmed.hasPrefix(rootPrefix) {
            trimmed.removeFirst(rootPrefix.count)
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        var expression = "^"
        var characters = Array(trimmed)[...]
        while let character = characters.popFirst() {
            switch character {
            case "*" where characters.first == "*":
                characters.removeFirst()
                if characters.first == "/" {
                    characters.removeFirst()
                    expression += "(.*/)?"
                } else {
                    expression += ".*"
                }

            case "*":
                expression += "[^/]*"

            case "?":
                expression += "[^/]"

            default:
                expression += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return expression + folderSuffix
    }

    /// Whether `glob` matches `path` or a folder holding it, or that its
    /// expression doesn't compile.
    static func answer(_ glob: String, _ path: String) -> Answer {
        guard let regex = try? NSRegularExpression(pattern: expression(for: glob)) else {
            return .unreadable
        }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) == nil ? .misses : .matches
    }
}
