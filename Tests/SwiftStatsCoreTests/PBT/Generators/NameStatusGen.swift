//
//  NameStatusGen.swift
//  SwiftStatsCoreTests
//
//  `git diff --name-status -z` listings for P14.2, as SwiftMutator's
//  selection asks git for them: entries of every status git writes, copies
//  and renames often, with scores from 0 to 100, and paths that `-z`
//  leaves unquoted: plain, holding a space, a tab, a line break or a CR,
//  accented either way, starting with a combining mark or a byte order
//  mark (design B36), spelled like a status (`D`, `R100`), or of any
//  fragments. No path is empty and none
//  holds NUL, as git writes none. A listing is sometimes cut: before an
//  entry, just after its status, or after the first path of a copy or
//  rename. Every list is ordered simplest first, so a failure shrinks
//  toward its plainest form.
//

import PropertyBased

/// Generators of `git diff --name-status -z` listings.
enum NameStatusGen {
    /// Paths: plain, holding a space, a tab, a line break or a CR, accented
    /// both ways, starting with a combining mark or a byte order mark (which
    /// Foundation's UTF-8 decoding drops, design B36), and spelled like a
    /// status.
    static let paths = [
        "a.swift", "Sources/A.swift", "a b.swift", "x\ty.swift", "x\ny.swift", "x\ry.swift", "Caf\u{E9}.swift",
        "Cafe\u{301}.swift", "\u{301}a.swift", "\u{FEFF}a.swift", "D", "M", "R100", "C050", "A"
    ]
    /// The largest score (forced: a percentage).
    static let largestScore = 100
    /// How many entries a listing has (assumed: enough for a copy or
    /// rename to sit between others, short enough to read when shrunk).
    static let entryCount = 0...6
    /// How many fragments an any-fragment path has (assumed).
    static let fragmentCount = 1...3
    /// The largest entry index and field count a cut draws before they
    /// are taken modulo the listing's (assumed: past the longest listing).
    static let cutRange = 0...7
    /// What a path of fragments is when shrinking emptied it.
    static let fallbackPath = "p"
    /// What stands for NUL in a path of fragments.
    static let nulReplacement = "?"

    /// Weight of drafted paths and of plain statuses.
    static let commonWeight = 3.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of a copy or a rename.
    static let twoPathWeight = 2.0
    /// The share of cut listings.
    static let cutRate: Float = 0.5

    /// A path: a drafted one, or fragments with no NUL.
    static let path = Gen.frequency(
        (commonWeight, Pick.element(of: paths)),
        (
            classWeight,
            UnicodeGen.inlineFragment.array(of: fragmentCount).map { fragments in
                let joined = fragments.joined().unicodeScalars
                    .map { $0 == "\u{0}" ? nulReplacement : String($0) }
                    .joined()
                return joined.isEmpty ? fallbackPath : joined
            }
        )
    )

    /// A status: any, a copy or a rename often.
    static let status = Gen.frequency(
        (commonWeight, Pick.element(of: NameStatusEntry.Status.allCases)),
        (twoPathWeight, Pick.element(of: [NameStatusEntry.Status.renamed, .copied]))
    )

    /// One entry: a status, a score, and as many paths as it names.
    static let entry = zip(status, Gen<Int>.value(in: 0...largestScore), path, path)
        .map { status, score, first, second in
            NameStatusEntry(status: status, score: score, paths: status.hasTwoPaths ? [first, second] : [first])
        }

    /// Where a listing is cut, if it is.
    static let cut = zip(Gen<Int>.value(in: cutRange), Gen<Int>.value(in: cutRange))
        .map { entry, kept in NameStatusDraft.Cut(entry: entry, kept: kept) }
        .optional(valueRate: cutRate)

    /// P14.2's input: a listing, sometimes cut.
    static let listing = zip(entry.array(of: entryCount), cut)
        .map { entries, cut in NameStatusDraft(entries: entries, cut: cut) }
        .eraseToAny()
}
