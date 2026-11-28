//
//  GlobPattern.swift
//  SwiftStatsCore
//
//  Path globs for `.swiftstats.yml` (PRD §10.1), matched against paths
//  relative to the package root: `*` and `?` stay within one path component,
//  `?` matching one Unicode scalar, and `**` spans any number of them, stars
//  read two at a time from the left. Every match extends to the paths under
//  it, wildcard or not (design B20, decided U8): a glob matches a path when
//  it matches the whole path or a folder holding it, so `Sources/Generated`
//  excludes that folder, and `Gen*` excludes `Generated/x.swift`. Line
//  breaks (U+000A to U+000D, U+0085, U+2028, U+2029) are the exception:
//  `**` and that extension stop at one, and one ending the path is ignored,
//  `\r\n` counting as one. The glob is read in Characters, so a `*`, `?` or
//  `/` that a combining mark joins is ordinary text.
//  The glob is matched directly (design B27), not through a regular
//  expression: one pass over the path's scalars per piece of the glob keeps
//  the set of places the pieces so far can end, so a match takes time
//  proportional to the glob's length times the path's, whatever the glob's
//  stars, and nothing backtracks. It answers exactly as the regular
//  expression it replaced did.
//

/// A path glob.
struct GlobPattern: Hashable {
    /// A piece of a glob.
    private enum Piece {
        /// `**` not followed by `/`: any run of scalars but line breaks.
        case anything
        /// `**/`: nothing, or any run of scalars but line breaks that ends
        /// in `/`.
        case folders
        /// `?`: one scalar but `/`.
        case scalar
        /// `*`: any run of scalars but `/`, line breaks among them.
        case star
        /// Any other Character of the glob, matching its own scalars.
        case text([Unicode.Scalar])
    }

    /// The prefix a pattern may start with, meaning the package root.
    private static let rootPrefix = "./"
    /// The scalar that separates path components.
    private static let separator: Unicode.Scalar = "/"
    /// The line breaks `**` and the folder extension stop at, and one of
    /// which may end the path: line feed, vertical tab, form feed, carriage
    /// return, next line, line separator and paragraph separator.
    private static let lineBreaks: Set<Unicode.Scalar> = [
        "\n", "\u{0B}", "\u{0C}", "\r", "\u{85}", "\u{2028}", "\u{2029}"
    ]
    /// The pair of line breaks that counts as one at the end of the path.
    private static let carriageReturnLineFeed: [Unicode.Scalar] = ["\r", "\n"]

    /// The pattern as written, without a leading `./` or trailing `/`.
    let pattern: String
    /// The pattern's pieces, in order.
    private let pieces: [Piece]

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
        pieces = Self.pieces(of: trimmed)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pattern == rhs.pattern
    }

    /// The pieces of a glob, read in Characters, two stars at a time:
    /// `**/` is `folders`, any other `**` is `anything`, `*` is `star` and
    /// `?` is `scalar`, so `***` is `anything` then `star`.
    private static func pieces(of glob: String) -> [Piece] {
        var read: [Piece] = []
        var characters = Array(glob)[...]
        while let character = characters.popFirst() {
            switch character {
            case "*" where characters.first == "*":
                characters.removeFirst()
                if characters.first == "/" {
                    characters.removeFirst()
                    read.append(.folders)
                } else {
                    read.append(.anything)
                }

            case "*":
                read.append(.star)

            case "?":
                read.append(.scalar)

            default:
                read.append(.text(Array(character.unicodeScalars)))
            }
        }
        return read
    }

    /// Where `piece` can end in `scalars`, given where it can start.
    private static func advance(_ reached: [Bool], over piece: Piece, in scalars: [Unicode.Scalar]) -> [Bool] {
        switch piece {
        case .anything:
            return runs(from: reached, in: scalars) { lineBreaks.contains($0) }

        case .folders:
            let spans = runs(from: reached, in: scalars) { lineBreaks.contains($0) }
            return reached.indices.map { index in
                reached[index] || (index > 0 && scalars[index - 1] == separator && spans[index - 1])
            }

        case .scalar:
            var next = Array(repeating: false, count: reached.count)
            for index in scalars.indices where reached[index] && scalars[index] != separator {
                next[index + 1] = true
            }
            return next

        case .star:
            return runs(from: reached, in: scalars) { $0 == separator }

        case .text(let text):
            var next = Array(repeating: false, count: reached.count)
            for index in reached.indices where reached[index] && index + text.count <= scalars.count {
                if scalars[index..<(index + text.count)].elementsEqual(text) {
                    next[index + text.count] = true
                }
            }
            return next
        }
    }

    /// Where a run of scalars, none of them `stops`, can end in `scalars`,
    /// given where it can start: one pass that opens at a start and closes
    /// at a scalar the run can't hold.
    private static func runs(
        from reached: [Bool],
        in scalars: [Unicode.Scalar],
        stoppingAt stops: (Unicode.Scalar) -> Bool
    ) -> [Bool] {
        var next = Array(repeating: false, count: reached.count)
        var open = false
        for index in reached.indices {
            open = open || reached[index]
            next[index] = open
            if index < scalars.count, stops(scalars[index]) {
                open = false
            }
        }
        return next
    }

    /// Where the end of `scalars` may be taken to be: the end itself, or
    /// just before one line break that ends them, `\r\n` counting as one
    /// (so never between its `\r` and `\n`).
    private static func ends(of scalars: [Unicode.Scalar]) -> [Int] {
        var places = [scalars.count]
        let pair = carriageReturnLineFeed
        if scalars.count >= pair.count, scalars.suffix(pair.count).elementsEqual(pair) {
            places.append(scalars.count - pair.count)
        } else if let last = scalars.last, lineBreaks.contains(last) {
            places.append(scalars.count - 1)
        }
        return places
    }

    /// Whether the glob matches `path`, or a folder that contains it.
    ///
    /// `reached[index]` says whether the pieces so far can match the path's
    /// first `index` scalars. After the last piece, the folder extension (a
    /// `/`, then any run but line breaks) may follow, and what is left must
    /// be nothing or one ending line break.
    func matches(_ path: String) -> Bool {
        let scalars = Array(path.unicodeScalars)
        var reached = Array(repeating: false, count: scalars.count + 1)
        reached[0] = true
        for piece in pieces {
            reached = Self.advance(reached, over: piece, in: scalars)
            guard reached.contains(true) else {
                return false
            }
        }
        let folder = Self.advance(
            Self.advance(reached, over: .text([Self.separator]), in: scalars),
            over: .anything,
            in: scalars
        )
        return Self.ends(of: scalars).contains { reached[$0] || folder[$0] }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pattern)
    }
}
