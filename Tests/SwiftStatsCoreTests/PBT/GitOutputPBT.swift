import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of reading git's output (PRD §8 divergent clones, M6 design
/// §6.1, design §4.1.7): the hunks of a rendered zero-context diff come
/// back by old path from the package, in order, CRLF files and every
/// quoting git does included (P14.1, design B5, B34, B35); and the paths
/// of a rendered `--name-status -z` listing are the last path of every
/// entry that isn't a deletion, in order, a byte order mark leading a path
/// kept (B36), a truncated listing giving its whole entries' paths and
/// never trapping (P14.2). P14.1 reads the rendered bytes through
/// `GitChanges.text(of:)` and `GitChanges.hunks(inDiff:packagePath:)`, as
/// `hunks(from:to:…)` reads git's; P14.2 reads them through
/// `MutationWorkCopy.decodedPaths(_:)` and
/// `MutationChanges.changedPaths(_:)`, as `MutationChanges.read` does.
/// `DiffHunkTests`, `MutationMergeTests` and
/// `MutationWorkCopyOverlayTests` hold the fixed examples, git's own
/// output among them; each property here has its own, calling its shared
/// check, and meta-tests that feed a planted defect's output to that
/// check.
@Suite("git output: properties", .tags(.pbt))
struct GitOutputPBT {
    /// What reading a name-status listing gives: its paths, or the failure
    /// decoding its fields gave.
    typealias Listing = Result<[String], any Error>

    /// P14.1's base runs, over the engine's 100: rendering, reading and
    /// labelling a diff of at most four files costs under a millisecond.
    /// The rarest antecedent, an octal escape followed by an octal digit,
    /// comes in 44 of the meta-test's 1,000 diffs (design D14: `(1 -
    /// 0.044)^330`, about 4 * 10^-7, is the most a run misses it; 100 runs
    /// would miss it about 10^-2 of the time), and a renamed file in the
    /// package with hunks in 47; a sibling folder's file with hunks, the
    /// one input on which a package test matching a folder by its name's
    /// start shows, comes in 69.
    static let diffRuns = 330
    /// What P14.1's tally counts when a changed line ending in CR comes
    /// just before another hunk of a file in the package.
    static let crBeforeHunk = "a CR-ended changed line before another hunk of a file in the package"
    /// What it counts when a changed line ending in CR comes just before
    /// the next file's header, and losing that header would show.
    static let crBeforeFile = "a CR-ended changed line before the next file's header, which would show"
    /// What it counts when a path in the package is quoted.
    static let quotedPath = "a quoted path in the package"
    /// What it counts when a path in the package holds a control git
    /// writes as a letter other than `t` and `n`.
    static let letterEscape = "a path in the package holding a control git writes as a letter, not t or n"
    /// What it counts when a path in the package holds an octal escape.
    static let octalEscape = "an octal escape in a path in the package"
    /// What it counts when an octal escape is followed by an octal digit,
    /// which the escape's three digits must not take.
    static let octalThenDigit = "an octal escape followed by an octal digit in a path in the package"
    /// What it counts when an old-path line in the package ends in a tab.
    static let tabbedPath = "an old-path line in the package ending in a tab"
    /// What it counts when a path's first component below the package
    /// starts with a mark.
    static let markFirst = "a path whose first component below the package starts with a mark"
    /// What it counts when a file with hunks lies in a sibling folder.
    static let sibling = "a file with hunks in a folder whose name starts with the package's"
    /// What it counts when a file with hunks lies outside the package.
    static let outside = "a file with hunks outside the package"
    /// What it counts when an added file has hunks.
    static let added = "an added file with hunks"
    /// What it counts when a deleted file in the package has hunks.
    static let deleted = "a deleted file in the package with hunks"
    /// What it counts when a renamed file in the package has hunks.
    static let renamed = "a renamed file in the package with hunks"
    /// What it counts when a file in the package gives no hunks.
    static let noHunks = "a file in the package giving no hunks"
    /// What it counts when a hunk in the package leaves its count of 1 out.
    static let omittedOne = "a count of 1 left out"
    /// What it counts when a hunk in the package has a count of 0.
    static let zeroCount = "a count of 0"
    /// What it counts when a hunk in the package starts or counts at
    /// `Int.max`.
    static let largest = "the largest start or count"
    /// What it counts when a removed line reads as an old-path line before
    /// a later hunk of its file, in the package.
    static let fakePathLine = "a removed line like an old-path line before a later hunk of its file"
    /// What it counts when a changed line isn't UTF-8.
    static let notUTF8 = "a changed line that isn't UTF-8"
    /// What it counts when the headers write the package in the other
    /// normalization form, and a file in it has hunks.
    static let otherForm = "the package written in the other normalization form"
    /// What it counts when the package is the repository and a file has
    /// hunks.
    static let atTop = "a package at the top with hunks"
    /// The antecedents P14.1 must reach at least once each.
    static let diffAntecedents = [
        crBeforeHunk, crBeforeFile, quotedPath, letterEscape, octalEscape, octalThenDigit, tabbedPath, markFirst,
        sibling, outside, added, deleted, renamed, noHunks, omittedOne, zeroCount, largest, fakePathLine, notUTF8,
        otherForm, atTop
    ]
    /// The controls git writes as a letter other than `t` and `n`.
    static let letterControls: Set<UInt8> = [0x07, 0x08, 0x0B, 0x0C, 0x0D]
    /// The scalars a first component may start with that join the `/`
    /// before it.
    static let markScalars = Set(GitDiffGen.marks.joined().unicodeScalars)

    /// A diff of a CRLF file of three hunks, one removing a blank line,
    /// then another CRLF file of one hunk, in the package `Pkg`: every
    /// hunk header after the first, and the second file's header, follow a
    /// line ending in CR LF (design B5).
    static let crlfDiff = DiffDraft(
        package: "Pkg",
        written: "Pkg",
        files: [
            plainFile(1, ending: .carriageReturnLineFeed, hunks: [
                hunk(2, 1), hunk(4, 2, removed: ["", "let e = 5"]), hunk(8, 1)
            ]),
            plainFile(2, ending: .carriageReturnLineFeed, hunks: [hunk(3, 1)])
        ]
    )

    /// A diff at the reader's edges, for the package `Café` written
    /// decomposed: a path quoted for a CR and a BEL (design B34); a renamed
    /// file whose path is written with octal escapes, its lines mixed; a
    /// path with a space and a mark starting it (B35); a sibling folder's
    /// file; a deleted file at `Int.max`; a removed line like an old-path
    /// line before a later hunk; an added file; a mode change.
    static let edgeDiff = DiffDraft(
        package: "Caf\u{E9}",
        written: "Cafe\u{301}",
        files: [
            markedFile(1, place: .inPackage, folders: ["x\ry", "b\u{7}z"], mark: nil, hunks: [hunk(5, 0)]),
            DiffFileDraft(
                kind: .renamed,
                place: .inPackage,
                folders: ["R\u{E9}sum\u{E9}", "c\u{1}d"],
                mark: nil,
                number: 2,
                octalHigh: true,
                ending: .mixed,
                hunks: [hunk(7, 3), hunk(20, 1)],
                endsWithoutNewline: true
            ),
            markedFile(3, place: .inPackage, folders: ["a b"], mark: "\u{301}", hunks: [hunk(1, 1)]),
            file(4, kind: .changed, place: .sibling, hunks: [hunk(9, 1)]),
            file(5, kind: .deleted, place: .inPackage, hunks: [hunk(Int.max, Int.max)]),
            plainFile(6, ending: .lineFeed, hunks: [hunk(2, 1, removed: ["-- a/Fake.swift"]), hunk(6, 2)]),
            file(7, kind: .added, place: .newFile, hunks: [hunk(0, 0)]),
            file(8, kind: .modeOnly, place: .inPackage, hunks: [])
        ]
    )

    /// A diff read for a package at the top: files in every place but a new
    /// file's, so each in the package, two of them starting with a mark.
    static let topDiff = DiffDraft(
        package: "",
        written: "",
        files: [
            file(1, kind: .changed, place: .elsewhere, hunks: [hunk(1, 2)]),
            markedFile(2, place: .sibling, folders: [], mark: "\u{FE0F}", hunks: [hunk(3, 1)]),
            markedFile(3, place: .parent, folders: ["\u{600}x"], mark: nil, hunks: [hunk(4, 0)]),
            markedFile(4, place: .inPackage, folders: [], mark: "\u{903}", hunks: [hunk(5, 1), hunk(6, 1)])
        ]
    )

    /// Records an issue naming `subject`, in ASCII, for each law in `laws`
    /// that fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record(Comment(rawValue: PBTTrace.ascii("\(subject) fails: it \(law.law)")))
        }
        return laws.allSatisfy(\.holds)
    }

    /// `paths` as their scalars, for comparing paths scalar for scalar.
    static func scalars(_ paths: some Sequence<String>) -> Set<[Unicode.Scalar]> {
        Set(paths.map { Array($0.unicodeScalars) })
    }

    /// `hunks` by path, sorted by path, each hunk as `(start,count)`.
    static func shown(_ hunks: [String: [DiffHunk]]) -> String {
        hunks.sorted { $0.key < $1.key }
            .map { key, list in "\(key.debugDescription): " + list.map { "(\($0.start),\($0.count))" }.joined() }
            .joined(separator: ", ")
    }

    /// Whether git writes `byte` of `file`'s path in octal: a control with
    /// no letter, the delete, or a byte past ASCII where the file quotes
    /// those in octal.
    static func needsOctal(_ byte: UInt8, _ file: DiffFileDraft) -> Bool {
        DiffDraft.needsQuoting(byte, octalHigh: file.octalHigh) && DiffDraft.letter(for: byte) == nil
    }

    /// Whether a byte of `bytes`, `file`'s path, that git writes in octal
    /// is followed by an octal digit.
    static func octalBeforeDigit(_ bytes: [UInt8], _ file: DiffFileDraft) -> Bool {
        zip(bytes, bytes.dropFirst()).contains { byte, next in
            needsOctal(byte, file) && (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(next)
        }
    }

    /// The files of `draft` that give hunks, by index: in the package,
    /// with hunks to give.
    static func givingFiles(of draft: DiffDraft) -> [Int] {
        draft.files.indices.filter { index in
            let file = draft.files[index]
            return file.givesHunks && file.hunks.isEmpty == false && draft.key(of: file) != nil
        }
    }

    /// The classes of `lines`, `draft`'s, in P14.1's tally, where the files
    /// at `giving` give hunks: a CR-ended changed line before a hunk header
    /// or a file header that matters, and a removed line like an old-path
    /// line before a later hunk.
    static func lineLabels(of draft: DiffDraft, lines: [DiffDraft.Line], giving: Set<Int>) -> [String] {
        let pathLine = Array("--- ".utf8)
        var labels: [String] = []
        for (line, next) in zip(lines, lines.dropFirst()) {
            guard case let .changed(file, endsInCR) = line.role, endsInCR else {
                continue
            }
            switch next.role {
            case .hunkHeader(let nextFile) where giving.contains(nextFile):
                labels.append(crBeforeHunk)

            case .fileHeader(let nextFile):
                let hasHunks = draft.files[nextFile].hunks.isEmpty == false
                if giving.contains(nextFile) || (giving.contains(file) && hasHunks) {
                    labels.append(crBeforeFile)
                }

            default:
                break
            }
        }
        for (index, line) in lines.enumerated() {
            guard case .changed(let file, _) = line.role, giving.contains(file) else {
                continue
            }
            guard line.bytes.starts(with: pathLine) else {
                continue
            }
            if lines[(index + 1)...].contains(where: { $0.role == .hunkHeader(file: file) }) {
                labels.append(fakePathLine)
            }
        }
        return labels
    }

    /// The classes `draft` falls in, for P14.1's tally and the generator's
    /// meta-test.
    static func diffLabels(of draft: DiffDraft) -> [String] {
        let lines = draft.lines
        let givingIndices = givingFiles(of: draft)
        let giving = givingIndices.map { draft.files[$0] }
        let paths = giving.map { "a/" + (draft.oldPath(of: $0) ?? "") }
        let pathBytes = paths.map { Array($0.utf8) }
        let quoted = zip(giving, paths).map { file, path in DiffDraft.quoted(path, octalHigh: file.octalHigh) }
        let hunks = giving.flatMap(\.hunks)
        let withHunks = draft.files.filter { $0.hunks.isEmpty == false }
        let outsideFiles = withHunks.filter { $0.place != .newFile && draft.key(of: $0) == nil && $0.givesHunks }
        let inPackage = draft.files.filter { draft.key(of: $0) != nil }
        let changed = lines.filter { line in
            guard case .changed = line.role else {
                return false
            }
            return true
        }
        .map(\.bytes)
        var labels = [
            (quoted.contains { $0.hasPrefix("\"") }, quotedPath),
            (pathBytes.contains { $0.contains(where: letterControls.contains) }, letterEscape),
            (zip(giving, pathBytes).contains { file, bytes in bytes.contains { needsOctal($0, file) } }, octalEscape),
            (zip(giving, pathBytes).contains { file, bytes in octalBeforeDigit(bytes, file) }, octalThenDigit),
            (quoted.contains { $0.contains(" ") }, tabbedPath),
            (giving.contains { draft.key(of: $0)?.unicodeScalars.first.map(markScalars.contains) == true }, markFirst),
            (outsideFiles.contains { $0.place == .sibling && draft.package.isEmpty == false }, sibling),
            (outsideFiles.isEmpty == false, outside),
            (withHunks.contains { $0.kind == .added }, added),
            (giving.contains { $0.kind == .deleted }, deleted),
            (giving.contains { $0.kind == .renamed }, renamed),
            (inPackage.contains { $0.givesHunks == false || $0.hunks.isEmpty }, noHunks),
            (hunks.contains { $0.count == 1 && $0.writesOne == false }, omittedOne),
            (hunks.contains { $0.count < 1 }, zeroCount),
            (hunks.contains { $0.start == Int.max || $0.count == Int.max }, largest),
            (changed.contains { String(bytes: $0, encoding: .utf8) == nil }, notUTF8),
            (
                giving.isEmpty == false && Array(draft.package.unicodeScalars) != Array(draft.written.unicodeScalars),
                otherForm
            ),
            (giving.isEmpty == false && draft.package.isEmpty, atTop)
        ]
        .filter(\.0)
        .map(\.1)
        labels += Set(lineLabels(of: draft, lines: lines, giving: Set(givingIndices))).sorted()
        return labels
    }

    /// Whether `read`, the hunks read from `draft`'s diff, are the model's:
    /// the same paths, scalar for scalar, each with the same hunks in the
    /// same order. Records an issue for each law that fails.
    static func checkHunks(_ draft: DiffDraft, read: [String: [DiffHunk]]) -> Bool {
        let expected = draft.expected
        var laws = [
            (
                scalars(read.keys) == scalars(expected.keys),
                "files hunks under \(read.keys.sorted()), expected \(expected.keys.sorted())"
            )
        ]
        for (path, hunks) in expected.sorted(by: { $0.key < $1.key }) where read[path] != hunks {
            laws.append((false, "gives \(path.debugDescription) [\(shown(read))], expected [\(shown([path: hunks]))]"))
        }
        return holds(laws, subject: "reading the diff")
    }

    // MARK: P14.1

    /// Invariant: reading a rendered zero-context diff gives each file
    /// whose old path lies in the package, and that has hunks to give, its
    /// hunks' old sides in order, under its path from the package, scalar
    /// for scalar; a new file, a file outside the package, and a file
    /// whose mode alone changed or that was renamed unchanged give none.
    /// Why it holds: `GitChanges.hunks(inDiff:packagePath:)`'s doc comment
    /// (old-side ranges by old path relative to the package; new files and
    /// files outside the package have none; lines end at each LF, design B5
    /// and U9), `unquoted`'s (every escape git writes, B34) and
    /// `relative`'s (components, the `/`s among scalars, B35); PRD §8.
    /// Why it might not: paths are valid UTF-8 and end in `.swift`, as
    /// GitChanges' pathspec and core.quotepath off give; numbers fit an
    /// `Int`, as `largestCount` pins; no two files share an old path, as
    /// `-M` without `-C` gives; header lines end in LF alone and only
    /// changed lines in CR LF, as git writes them (step 15a's recorded
    /// diff).
    /// Oracle: the generating model (`DiffDraft.expected`); planted
    /// defects: lines split on Characters (B5 undone), the last hunk alone
    /// kept, a left-out count read as 0, a CR, BEL or other letter escape
    /// read as its letter (B34 undone), a path found in the package by a
    /// Character prefix (B35 undone), and a sibling folder read as the
    /// package, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "a rendered diff's hunks come back by old path from the package, in order, and only for files in it",
        .timeLimit(PBTBudget.timeLimit)
    )
    func hunksReadBack() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.diffRuns), input: GitDiffGen.diff) { draft in
            PBTTrace.note(draft)
            Self.diffLabels(of: draft).forEach(tally.fire)
            let read = GitChanges.hunks(inDiff: GitChanges.text(of: draft.data), packagePath: draft.package)
            if Self.checkHunks(draft, read: read) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.diffAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }
}
