//
//  GlobPattern.swift
//  SwiftStatsCore
//
//  Path globs for `.swiftstats.yml` (PRD §10.1), matched against paths
//  relative to the package root: `*` and `?` stay within one path component,
//  `**` spans any number of them, and a pattern with no wildcard also
//  matches everything under it, so `Sources/Generated` excludes that folder.
//  A run of `**` and `**/` becomes one piece of the regex, and the lone `*`
//  that ends an odd run follows `(.*/)?` rather than `.*`. Both match exactly
//  what the run matched, so a long run can't make a failed match backtrack
//  exponentially, and repeated odd runs backtrack no more than `**/*/` does.
//

import Foundation

/// A path glob.
struct GlobPattern: Hashable {
    /// A piece of a glob's regular expression.
    private enum Piece: Equatable {
        /// `**` not followed by `/`: `.*`, any characters but line breaks.
        case anything
        /// `**/`: `(.*/)?`, nothing, or any characters but line breaks that
        /// end in `/`.
        case folders
        /// `*`: `[^/]*`, any characters but `/`, line breaks among them.
        case star
        /// Any other part of the glob, as regular-expression text.
        case text(String)

        /// Whether the piece comes from `**`.
        var isDoubleStar: Bool {
            self == .anything || self == .folders
        }

        /// The piece as regular-expression text.
        var regex: String {
            switch self {
            case .anything:
                ".*"

            case .folders:
                "(.*/)?"

            case .star:
                "[^/]*"

            case .text(let text):
                text
            }
        }
    }

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
    ///
    /// `**/` is `(.*/)?`, any other `**` is `.*`, `*` is `[^/]*` and `?` is
    /// `[^/]`, read two stars at a time, so `***` is `.*[^/]*`. Next to each
    /// other, `.*` and `(.*/)?` become one piece: `.*`, unless both are
    /// `(.*/)?`. That matches exactly what the pair did, since `.*` takes any
    /// characters but line breaks, `/` among them. A `.*` just before `[^/]*`
    /// becomes `(.*/)?`, so `***` is written `(.*/)?[^/]*`, which matches
    /// exactly what `.*[^/]*` did: a `/` can only fall in the first part, and
    /// that part can end at the last one. Both keep a run of stars from
    /// adding backtracking of its own when the match fails: a long run takes
    /// no longer than `**`, and `***/` repeated no longer than `**/*/`
    /// repeated.
    private static func regex(for glob: String) -> String {
        var pieces: [Piece] = []
        var characters = Array(glob)[...]
        while let character = characters.popFirst() {
            let piece: Piece
            switch character {
            case "*" where characters.first == "*":
                characters.removeFirst()
                if characters.first == "/" {
                    characters.removeFirst()
                    piece = .folders
                } else {
                    piece = .anything
                }

            case "*":
                piece = .star

            case "?":
                piece = .text("[^/]")

            default:
                piece = .text(NSRegularExpression.escapedPattern(for: String(character)))
            }
            append(piece, to: &pieces)
        }
        return pieces.map(\.regex).joined()
    }

    /// Adds `piece` to `pieces`, joining two `**` pieces in a row into one,
    /// and making a `.*` just before `[^/]*` into `(.*/)?`.
    private static func append(_ piece: Piece, to pieces: inout [Piece]) {
        if piece == .star, pieces.last == .anything {
            pieces[pieces.count - 1] = .folders
            pieces.append(piece)
            return
        }
        guard let last = pieces.last, last.isDoubleStar, piece.isDoubleStar else {
            pieces.append(piece)
            return
        }
        pieces[pieces.count - 1] = last == .folders && piece == .folders ? .folders : .anything
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
