//
//  DiffFileDraft.swift
//  SwiftStatsCoreTests
//
//  One file's part of a zero-context diff as decisions, for P14.1: what
//  happened to the file (changed, added, deleted, renamed with or without
//  changed lines, or only its mode changed), where its old path lies (in
//  the package, beside it in a sibling folder whose name starts with the
//  package's, in the folder above it, elsewhere, or nowhere for a new
//  file), the folders of its path below that folder and what starts the
//  first component there (design B35), whether a quoted path writes its
//  non-ASCII bytes as octal escapes (as git does with core.quotepath on;
//  the reader takes either), how its changed lines end (LF; CR LF, as git
//  writes a CRLF file's changed lines, design B5 and U9; or the two
//  alternating), its hunks, and whether git notes that its last line has
//  no newline. Its number in the diff names it (`F<number>.swift`), so no
//  two files share a path.
//

/// One file's part of a zero-context diff as decisions.
struct DiffFileDraft: Hashable, Sendable {
    /// How a file's changed lines end.
    enum Ending: Hashable, Sendable, CaseIterable {
        /// Every one in CR LF, as git writes a CRLF file's.
        case carriageReturnLineFeed
        /// Every one in LF.
        case lineFeed
        /// CR LF and LF alternating, CR LF first.
        case mixed
    }

    /// What happened to the file.
    enum Kind: Hashable, Sendable, CaseIterable {
        /// It is new: its old path is `/dev/null`.
        case added
        /// Its lines changed.
        case changed
        /// It was deleted: its new path is `/dev/null`.
        case deleted
        /// Only its mode changed: no old-path line and no hunks.
        case modeOnly
        /// It was renamed unchanged: no old-path line and no hunks.
        case pureRename
        /// It was renamed and its lines changed.
        case renamed
    }

    /// Where the file's old path lies.
    enum Place: Hashable, Sendable, CaseIterable {
        /// Under `Elsewhere/`, outside a package that isn't the repository.
        case elsewhere
        /// In the package.
        case inPackage
        /// Nowhere: the file is new.
        case newFile
        /// In the folder above the package.
        case parent
        /// In the folder beside the package whose name is the package's
        /// last component and `x`.
        case sibling
    }

    /// How many changed lines a mixed file's endings take to repeat.
    static let mixedPeriod = 2

    /// What happened to the file.
    let kind: Kind
    /// Where its old path lies; `newFile` exactly when `kind` is `added`.
    let place: Place
    /// The folders of its path below that folder; none empty, none holding
    /// `/` or NUL.
    let folders: [String]
    /// What starts the first component below that folder, if anything.
    let mark: String?
    /// Its number in the diff, which names it.
    let number: Int
    /// Whether a quoted path writes its non-ASCII bytes as octal escapes.
    let octalHigh: Bool
    /// How its changed lines end.
    let ending: Ending
    /// Its hunks, in order; none when only its mode changed or it was
    /// renamed unchanged.
    let hunks: [DiffHunkDraft]
    /// Whether git notes, after its last changed line, that the file's last
    /// line has no newline.
    let endsWithoutNewline: Bool

    /// Whether the diff writes an old-path line (`--- `) for the file.
    var hasPathLines: Bool {
        kind != .modeOnly && kind != .pureRename
    }

    /// Whether the reader files its hunks under its old path, when that
    /// path lies in the package: it has an old path and hunks to give.
    var givesHunks: Bool {
        kind == .changed || kind == .deleted || kind == .renamed
    }

    /// Its name: `F`, its number, `.swift`.
    var name: String {
        "F\(number).swift"
    }

    /// The components of its path below its folder: its folders and its
    /// name, the mark starting the first.
    var components: [String] {
        var parts = folders + [name]
        parts[0] = (mark ?? "") + parts[0]
        return parts
    }

    /// Its path below its folder: the components joined by `/`.
    var relative: String {
        components.joined(separator: "/")
    }

    /// The file, numbered `number`.
    func named(_ number: Int) -> Self {
        Self(
            kind: kind,
            place: place,
            folders: folders,
            mark: mark,
            number: number,
            octalHigh: octalHigh,
            ending: ending,
            hunks: hunks,
            endsWithoutNewline: endsWithoutNewline
        )
    }

    /// Whether the changed line at `index` of the file's changed lines
    /// ends in CR before its LF.
    func endsInCarriageReturn(at index: Int) -> Bool {
        switch ending {
        case .carriageReturnLineFeed:
            return true

        case .lineFeed:
            return false

        case .mixed:
            return index.isMultiple(of: Self.mixedPeriod)
        }
    }
}
