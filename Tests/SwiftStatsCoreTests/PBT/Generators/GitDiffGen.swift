//
//  GitDiffGen.swift
//  SwiftStatsCoreTests
//
//  Zero-context diffs for P14.1, as GitChanges asks git for them. The
//  package is at the top or below it, its path plain, holding a space or
//  a tab, nested, accented (written in the headers in either normalization
//  form), or starting with a combining mark. Files are changed, added,
//  deleted, renamed with or without changed lines, or changed only in mode,
//  each in the package, beside it, above it, elsewhere, or new; their paths
//  are built of components that git quotes (every control git writes as a
//  letter escape or in octal, a quote, a backslash, a line break), that
//  hold a space (a tab then ends the path line), that are accented either
//  way or start with a Prepend scalar, or of any fragments; the first
//  component below the folder sometimes starts with a combining mark, a
//  joiner, a variation selector or a spacing mark, which joins the `/`
//  before it into one Character (design B35). A file's changed lines end
//  in LF, CR LF or the two alternating (design B5, U9), and hold any bytes
//  but LF: text that looks like an old-path line, a hunk header or a file
//  header, a lone CR, invalid UTF-8. Hunk starts and counts are small,
//  anywhere up to `Int.max`, or an edge. No drafted folder name spells a
//  package component, so a file is in the package exactly when its place
//  says so. Every list is ordered simplest first, so a failure shrinks
//  toward its plainest form.
//

import PropertyBased
@testable import SwiftStatsCore

/// Generators of zero-context diffs.
enum GitDiffGen {
    /// Package paths, as the reader is given them: the top, plain, holding
    /// a space or a tab, nested, and starting with a combining mark. None
    /// is a drafted folder name, nor a fragment folder name (those are
    /// lowercase words or single fragments), so no file in the folder above
    /// the package lands in it.
    static let packages = ["", "Pkg", "My Pkg", "Pkg/Kit", "\u{301}Pkg", "p\tq"]
    /// Accented package paths, precomposed and decomposed, which the
    /// headers may write in the other form. Neither is a drafted folder
    /// name.
    static let accentedPackages = ["Caf\u{E9}", "Cafe\u{301}"]
    /// Folder names a path is built of: plain, holding a space, accented
    /// both ways, quoted for a tab, a quote, a backslash, a CR, a BEL, a
    /// backspace, a vertical tab, a form feed, a line feed, another control
    /// before an octal digit (which its octal escape's three digits must not
    /// take) and the delete, starting with a Prepend scalar, and shaped like
    /// diff syntax.
    static let folderNames = [
        "Sources", "Core", "a b", "R\u{E9}sum\u{E9}", "Re\u{301}sume\u{301}", "x\ty", "q\"r", "back\\slash", "x\ry",
        "b\u{7}z", "s\u{8}", "v\u{B}", "f\u{C}", "x\ny", "c\u{1}7d", "del\u{7F}", "\u{600}x", "@@ -1 +1 @@", "-", "dev"
    ]
    /// What may start the first component below a file's folder: a
    /// combining mark, a joiner, a variation selector and a spacing mark,
    /// each of which joins the `/` before it into one Character (B35).
    static let marks = ["\u{301}", "\u{200D}", "\u{FE0F}", "\u{903}"]
    /// What a changed line is built of: code, nothing, text that looks like
    /// an old-path line (after the `-` a removed line starts with), a hunk
    /// header or a file header, a lone CR, a mark, a tab and a Prepend
    /// scalar.
    static let changedPieces = [
        "let a = 1", "", "-- a/Fake.swift", "-- \"a/Pkg/F1.swift\"", "@@ -1 +1 @@", "diff --git a/x b/x",
        "+++ b/y", "x\ry", "\u{301}", "\t", "\u{600}"
    ]
    /// Function contexts git writes after a hunk header's second `@@`.
    static let contexts = ["func alpha() {", "struct S {", "@@ -9 +9 @@", " -5,2"]
    /// How many files a diff has (assumed: enough for a file to follow a
    /// CRLF one, short enough to read when shrunk; design D7).
    static let fileCount = 0...4
    /// How many hunks a file has (assumed, as above).
    static let hunkCount = 0...3
    /// How many folders a path has below its place (assumed, as above).
    static let folderCount = 0...2
    /// How many changed lines a hunk draws on each side (assumed: a
    /// zero-context hunk's lines are never read, so a few show it).
    static let lineCount = 0...3
    /// How many pieces or fragments a changed line has (assumed, as above).
    static let pieceCount = 0...3
    /// How many fragments an any-fragment folder name has (assumed).
    static let fragmentCount = 1...3
    /// The largest small start (assumed: past any real file).
    static let smallStart = 999
    /// The largest small count (assumed: a zero-context hunk's usual).
    static let smallCount = 3
    /// Edge starts and counts: none, one, and the largest.
    static let edgeNumbers = [0, 1, Int.max]
    /// What a folder name of fragments is when shrinking emptied it.
    static let fallbackName = "p"
    /// What stands for a `/` or NUL in a folder name of fragments: a path
    /// never holds NUL, and a `/` would split it.
    static let pathReplacement = "?"

    /// Weight of plain values and common classes.
    static let commonWeight = 4.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of a changed file, beside each kind at `classWeight`: about
    /// one file in four is another kind.
    static let changedWeight = 3.0
    /// Weight of the plain package paths.
    static let plainPackageWeight = 3.0
    /// Weight of the accented package paths.
    static let accentedPackageWeight = 2.0
    /// Weight of a file in the package.
    static let inPackageWeight = 5.0
    /// Weight of a CRLF file (design B5).
    static let crlfWeight = 3.0
    /// The share of accented packages the headers write in the other
    /// normalization form.
    static let otherFormRate: Float = 0.6
    /// The share of paths whose first component starts with a mark.
    static let markRate: Float = 0.15
    /// The share of files quoting non-ASCII bytes in octal.
    static let octalRate: Float = 0.2
    /// The share of hunks writing a count of 1.
    static let writesOneRate: Float = 0.1
    /// The share of hunks with a function context.
    static let contextRate: Float = 0.5
    /// The share of files ending without a newline.
    static let noNewlineRate: Float = 0.15

    /// A package path and how the headers write it.
    static let package = zip(
        Gen.frequency(
            (plainPackageWeight, Pick.element(of: packages)),
            (accentedPackageWeight, Pick.element(of: accentedPackages))
        ),
        Gen.bool(otherFormRate)
    )
        .map { package, otherForm in
            let other = package == package.precomposedStringWithCanonicalMapping
                ? package.decomposedStringWithCanonicalMapping
                : package.precomposedStringWithCanonicalMapping
            return (package: package, written: otherForm ? other : package)
        }

    /// A folder name: a drafted one, or fragments with no `/` or NUL.
    static let folderName = Gen.frequency(
        (commonWeight, Pick.element(of: folderNames)),
        (
            classWeight,
            UnicodeGen.inlineFragment.array(of: fragmentCount).map { fragments in
                let name = fragments.joined().unicodeScalars
                    .map { $0 == "/" || $0 == "\u{0}" ? pathReplacement : String($0) }
                    .joined()
                return name.isEmpty ? fallbackName : name
            }
        )
    )

    /// A file's components below its folder, without its name: folders,
    /// and a mark to start the first component (the name, when there are
    /// none).
    static let folders = zip(folderName.array(of: folderCount), Pick.element(of: marks).optional(valueRate: markRate))

    /// A start: small, anywhere up to `Int.max`, or an edge.
    static let start = Gen.frequency(
        (commonWeight, Gen<Int>.value(in: 1...smallStart)),
        (classWeight, Gen<Int>.value(in: 0...Int.max)),
        (classWeight, Pick.element(of: edgeNumbers))
    )

    /// A count: small, anywhere up to `Int.max`, or an edge.
    static let count = Gen.frequency(
        (commonWeight, Gen<Int>.value(in: 0...smallCount)),
        (classWeight, Gen<Int>.value(in: 0...Int.max)),
        (classWeight, Pick.element(of: edgeNumbers))
    )

    /// A changed line's bytes: pieces, fragments and invalid UTF-8.
    static let changedLine = Gen.frequency(
        (commonWeight, Pick.element(of: changedPieces).map { Array($0.utf8) }),
        (classWeight, UnicodeGen.inlineFragment.map { Array($0.utf8) }),
        (classWeight, UnicodeGen.invalidBytes)
    )
    .array(of: pieceCount)
    .map { $0.flatMap(\.self) }

    /// One hunk.
    static let hunk = zip(
        start,
        count,
        Gen.bool(writesOneRate),
        zip(Gen<Int>.value(in: 1...smallStart), Gen<Int>.value(in: 0...smallCount)),
        Pick.element(of: contexts).optional(valueRate: contextRate),
        changedLine.array(of: lineCount),
        changedLine.array(of: lineCount)
    )
    .map { start, count, writesOne, new, context, removed, added in
        DiffHunkDraft(
            start: start,
            count: count,
            writesOne: writesOne,
            newStart: new.0,
            newCount: new.1,
            context: context,
            removed: removed,
            added: added
        )
    }

    /// What happened to a file: changed, mostly.
    static let kind = Gen.frequency(
        (changedWeight, Gen.always(DiffFileDraft.Kind.changed)),
        (classWeight, Pick.element(of: DiffFileDraft.Kind.allCases))
    )

    /// Where a file's old path lies, for a file that isn't new: in the
    /// package, mostly.
    static let place = Gen.frequency(
        (inPackageWeight, Gen.always(DiffFileDraft.Place.inPackage)),
        (classWeight, Pick.element(of: [DiffFileDraft.Place.sibling, .parent, .elsewhere]))
    )

    /// How a file's changed lines end: CR LF often.
    static let ending = Gen.frequency(
        (commonWeight, Gen.always(DiffFileDraft.Ending.lineFeed)),
        (crlfWeight, Gen.always(DiffFileDraft.Ending.carriageReturnLineFeed)),
        (classWeight, Gen.always(DiffFileDraft.Ending.mixed))
    )

    /// One file, numbered 0 until the diff numbers it.
    static let file = zip(
        kind,
        place,
        folders,
        Gen.bool(octalRate),
        ending,
        hunk.array(of: hunkCount),
        Gen.bool(noNewlineRate)
    )
    .map { kind, place, folders, octalHigh, ending, hunks, endsWithoutNewline in
        DiffFileDraft(
            kind: kind,
            place: kind == .added ? .newFile : place,
            folders: folders.0,
            mark: folders.1,
            number: 0,
            octalHigh: octalHigh,
            ending: ending,
            hunks: kind == .modeOnly || kind == .pureRename ? [] : hunks,
            endsWithoutNewline: endsWithoutNewline
        )
    }

    /// P14.1's input: a package and a diff of its files, each named by its
    /// number.
    static let diff = zip(package, file.array(of: fileCount))
        .map { package, files in
            DiffDraft(
                package: package.package,
                written: package.written,
                files: files.enumerated().map { index, file in file.named(index + 1) }
            )
        }
        .eraseToAny()
}
