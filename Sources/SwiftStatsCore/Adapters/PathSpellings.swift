//
//  PathSpellings.swift
//  SwiftStatsCore
//
//  The ways a tool can write a temporary directory's path. On macOS `/var`
//  and `/tmp` are symlinks into `/private`, and a tool that asks for its
//  working directory gets the `/private` spelling, while Foundation drops
//  `/private` when it resolves symlinks. A reason can redact a directory
//  only where a path ends, so that a folder beside it whose name starts
//  with its name keeps its path.
//

import Foundation

/// Spellings of a directory's path.
enum PathSpellings {
    /// The prefix macOS's `/var` and `/tmp` resolve under.
    private static let privatePrefix = "/private"
    /// What a path redacted where it ends must be followed by: a
    /// separator, a space, a quote, punctuation that ends it, or the end
    /// of the text.
    private static let pathEnd = #"(?=[/\s'"),:;.\]>]|$)"#

    /// `directory` as given, standardized, with symlinks resolved, and
    /// each with and without `/private`; longest first, since a shorter
    /// spelling can lie inside a longer one.
    static func of(_ directory: URL) -> [String] {
        var spellings = Set<String>()
        for path in [directory.standardizedFileURL.path, directory.resolvingSymlinksInPath().path] {
            spellings.insert(path)
            if path.hasPrefix(privatePrefix + "/") {
                spellings.insert(String(path.dropFirst(privatePrefix.count)))
            } else {
                spellings.insert(privatePrefix + path)
            }
        }
        return spellings.sorted { ($0.count, $0) > ($1.count, $1) }
    }

    /// `text` with each directory in `replacements`, however it is
    /// spelled, replaced by its placeholder, but only where a path ends:
    /// `/x/Pkg` is redacted in `/x/Pkg/A.swift`, not in `/x/PkgKit/A.swift`.
    static func redactedWherePathsEnd(_ text: String, replacing replacements: [(URL, String)]) -> String {
        var redacted = text
        for (directory, placeholder) in replacements {
            for spelling in of(directory) {
                let pattern = NSRegularExpression.escapedPattern(for: spelling) + pathEnd
                guard let expression = try? NSRegularExpression(pattern: pattern) else {
                    continue
                }
                redacted = expression.stringByReplacingMatches(
                    in: redacted,
                    range: NSRange(redacted.startIndex..., in: redacted),
                    withTemplate: NSRegularExpression.escapedTemplate(for: placeholder)
                )
            }
        }
        return redacted
    }
}
