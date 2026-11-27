//
//  ResultsFileGen.swift
//  SwiftStatsCoreTests
//
//  results.jsonl files (M6, design §2) for P3.4 to P3.7, drawn as
//  decisions (`ResultsFileDraft`): most start with a whole header, then
//  up to 16 lines of every kind the reader knows (headers with a whole
//  tree, none, or a `projectDelta` that does or doesn't rebuild an earlier
//  tree; `mutant` lines, most of them; `retired`, `control`, `end` and
//  `stopped` lines), lines of unknown kinds, lines that never read, and
//  lines with no bytes. Sessions are numbered 1 to 3, and lines name 1 to
//  4, so a line of a session no readable header started comes up. Each
//  typed line may be flawed (`ResultsLineDraft.FlawKind`), readable or
//  not; a header's nested `provenance.toolchain` or `swiftMutator`
//  written as a string comes most often among a header's flaws. Keys come
//  from a pool: three at one place that differ only in the
//  operator or the occurrence, one path in both its composed and its
//  decomposed spelling (one key to the reader), and two drawn from
//  `MutantKeyGen`. Lines break with LF or CRLF, the last one or not. In
//  `file` every header is in a format the reading rules name (1 to 4);
//  `anyFile`, P3.6's input, also draws newer formats. No header is in a
//  format below 1, which the reader reads but the rules say to refuse,
//  until that is decided (design D17). The labels the properties check
//  come from `ResultsFileModel`.
//

import PropertyBased
@testable import SwiftStatsCore

/// Generators of results files.
enum ResultsFileGen {
    /// The pool's fixed keys: three at one place, differing only in the
    /// occurrence or the operator, and one accented path composed and
    /// decomposed.
    static let fixedKeys = [
        libraryKey("RelationalBoundary", occurrence: 0),
        libraryKey("RelationalBoundary", occurrence: 1),
        libraryKey("SwapTernary", occurrence: 0),
        cafeKey("Sources/Caf\u{E9}.swift"),
        cafeKey(ResultsLineRenderer.cafePath)
    ]
    /// The line of the fixed keys in the library file.
    static let libraryLine = 3
    /// Their column.
    static let libraryColumn = 9
    /// The line of the fixed keys in the accented file.
    static let cafeLine = 12
    /// Their column.
    static let cafeColumn = 5
    /// How many pool keys are drawn from `MutantKeyGen` (assumed: two
    /// odd keys beside the fixed ones are enough to meet the rules).
    static let drawnKeyCount = 2
    /// The pool indices lines draw (forced: the fixed and drawn keys).
    static let keyIndices = 0...(fixedKeys.count + drawnKeyCount - 1)
    /// The sessions headers start (assumed: three are enough for a resume
    /// of a resume).
    static let headerSessions = 1...3
    /// The sessions other lines name: one more, which no header starts.
    static let lineSessions = 1...4
    /// How many lines follow the leading header (design D7: arrays of 12
    /// to 30 elements; assumed enough for two sessions and a retire).
    static let lineCount = 0...16
    /// How many keys a header's not-covered list names (assumed).
    static let listedKeys = 0...3
    /// How many keys a `retired` line names (assumed; SwiftMutator never
    /// writes an empty one, and it would retire nothing).
    static let retiredKeys = 1...3
    /// The largest slot a flaw draws: past any line's key count, so every
    /// key and many cut points are reached.
    static let largestSlot = 255
    /// The pool's tree indices.
    static let treeIndices = ResultsLineRenderer.trees.indices
    /// The formats the reader reads, newest first: 1 to 4, the formats
    /// SwiftMutator's docs name (assumed bound, design D17: the reader also
    /// reads formats below 1, where the docs say a reader refuses a format
    /// it doesn't know; that awaits the user's decision, and
    /// `ResultsFilePBT.formatsBelowOneRead` pins what the reader does).
    static let readableVersions = Array((1...ResultsFileModel.newestFormatVersion).reversed())
    /// A format far newer than any.
    static let farVersion = 99
    /// Newer formats, which refuse the file: the next two, a far one and
    /// the largest.
    static let newerVersions = [
        ResultsFileModel.newestFormatVersion + 1, ResultsFileModel.newestFormatVersion + 1 + 1, farVersion, Int.max
    ]
    /// The largest pick a reordering draws.
    static let largestPick = 99

    /// Weight of an intact line.
    static let intactWeight = 8.0
    /// Weight of an intact header, so most sessions read.
    static let intactHeaderWeight = 16.0
    /// Weight of an intact header in P3.6's files, so a newer header that
    /// doesn't otherwise read comes up.
    static let intactAnyHeaderWeight = 1.0
    /// Weight of the other flaws, together.
    static let flawWeight = 1.0
    /// Weight of a header's nested object mistyped, beside its other flaws:
    /// drawn only as one of them, a file read as results skipping a header
    /// whose `provenance.toolchain` is mistyped came in 2 of the meta-test's
    /// 1,000 files, and a reader that takes such a header passed every
    /// property; this weight brings it to 62 of 1,000, past what design D14
    /// needs for P3.4's 300 runs (`(1 - 0.062)^300`, about 4 * 10^-9).
    static let nestedHeaderWeight = 5.0
    /// Weight of a `mutant` line among the lines.
    static let mutantWeight = 6.0
    /// Weight of a header among the lines.
    static let headerWeight = 2.0
    /// Weight of each other kind of line.
    static let kindWeight = 1.0
    /// Weight of a `retired` line among the lines.
    static let retiredWeight = 2.0
    /// Weight of a fixed key among the keys a line names, so keys meet.
    static let fixedKeyWeight = 4.0
    /// Weight of session 1 among the sessions a line names, and of the
    /// pool's first tree among the trees a header names, so lines meet
    /// their header and deltas their base.
    static let firstWeight = 3.0
    /// Weight of a value SwiftMutator writes among a line's choices.
    static let knownWeight = 12.0
    /// Weight of a reason SwiftMutator writes among an `end` line's, so
    /// one it doesn't write comes up.
    static let knownReasonWeight = 3.0
    /// Weight of a whole tree.
    static let wholeWeight = 3.0
    /// Weight of a `projectDelta`.
    static let deltaWeight = 3.0
    /// Weight of a newer format among `anyFile`'s.
    static let newerWeight = 1.0
    /// The share of files with a leading header.
    static let leadRate: Float = 0.75
    /// The share of files with no header at all: the leading one left out
    /// and every header line written as a `stopped` line, so files refused
    /// for want of a header, and files that are a `stopped` line, come up.
    static let headerlessRate: Float = 0.3
    /// The share of headers listing not-covered mutants.
    static let listsRate: Float = 0.85
    /// The share of `projectDelta`s that claim the tree they make.
    static let honestRate: Float = 0.75
    /// The share of files whose lines break with CRLF.
    static let crlfRate: Float = 0.25
    /// The share of files whose last line has a line break.
    static let finalBreakRate: Float = 0.85

    /// The pool index of a key a line names: a fixed key, most of the time.
    static let keyIndex = Gen.frequency(
        (fixedKeyWeight, Gen<Int>.value(in: 0...(fixedKeys.count - 1))),
        (kindWeight, Gen<Int>.value(in: fixedKeys.count...keyIndices.upperBound))
    )
    /// A session a line names: 1, most of the time.
    static let lineSession = Gen.frequency(
        (firstWeight, Gen.always(headerSessions.lowerBound)),
        (kindWeight, Gen<Int>.value(in: (headerSessions.lowerBound + 1)...lineSessions.upperBound))
    )
    /// A session a header starts: 1, most of the time.
    static let headerSession = Gen.frequency(
        (firstWeight, Gen.always(headerSessions.lowerBound)),
        (kindWeight, Gen<Int>.value(in: (headerSessions.lowerBound + 1)...headerSessions.upperBound))
    )
    /// A pool tree's index: the first, most of the time.
    static let treeIndex = Gen.frequency(
        (firstWeight, Gen.always(treeIndices.lowerBound)),
        (kindWeight, Gen<Int>.value(in: (treeIndices.lowerBound + 1)...(treeIndices.upperBound - 1)))
    )
    /// A flaw of a line: intact, most of the time.
    static let flaw = zip(flawKind(intact: intactWeight), Gen<Int>.value(in: 0...largestSlot))
        .map(ResultsLineDraft.Flaw.init)
    /// A flaw of a header: intact more often, and its nested objects
    /// mistyped more often than the other flaws.
    static let headerFlaw = zip(
        Gen.frequency(
            (intactHeaderWeight + flawWeight, flawKind(intact: intactHeaderWeight)),
            (nestedHeaderWeight, Gen.always(ResultsLineDraft.FlawKind.nestedMistyped))
        ),
        Gen<Int>.value(in: 0...largestSlot)
    )
    .map(ResultsLineDraft.Flaw.init)
    /// A flaw of a header in P3.6's files: intact less often.
    static let anyHeaderFlaw = zip(flawKind(intact: intactAnyHeaderWeight), Gen<Int>.value(in: 0...largestSlot))
        .map(ResultsLineDraft.Flaw.init)
    /// The tree a header records.
    static let tree = Gen.frequency(
        (wholeWeight, treeIndex.map(ResultsLineDraft.TreeDraft.whole)),
        (deltaWeight, zip(treeIndex, treeIndex, Gen.bool(honestRate)).map { base, target, honest in
            ResultsLineDraft.TreeDraft.delta(base: base, target: target, honest: honest)
        }),
        (kindWeight, Gen.always(ResultsLineDraft.TreeDraft.noTree))
    )
    /// Whether a header writes `mutantsNotCovered`.
    static let listsNotCovered = Gen.bool(listsRate)
    /// A header's not-covered list.
    static let notCovered = keyIndex.array(of: listedKeys)
    /// A format the reader reads.
    static let version = Pick.element(of: readableVersions)
    /// A format the reader reads, or a newer one.
    static let anyVersion = Gen.frequency(
        (kindWeight, Pick.element(of: readableVersions)),
        (newerWeight, Pick.element(of: newerVersions))
    )
    /// A header in a format the reader reads.
    static let header = zip(headerSession, version, tree, listsNotCovered, notCovered, headerFlaw)
        .map(ResultsLineDraft.HeaderDraft.init)
        .eraseToAny()
    /// A header in any format.
    static let anyHeader = zip(headerSession, anyVersion, tree, listsNotCovered, notCovered, anyHeaderFlaw)
        .map(ResultsLineDraft.HeaderDraft.init)
        .eraseToAny()
    /// A whole header recording a whole tree or none, in a format the
    /// reader reads: the line most files start with.
    static let leadHeader = zip(
        headerSession,
        version,
        treeIndex.map(ResultsLineDraft.TreeDraft.whole).optional(),
        listsNotCovered,
        notCovered
    )
    .map { session, version, tree, lists, notCovered in
        ResultsLineDraft.HeaderDraft(
            session: session,
            formatVersion: version,
            tree: tree ?? .noTree,
            listsNotCovered: lists,
            notCovered: notCovered,
            flaw: ResultsLineDraft.Flaw(kind: .intact, slot: 0)
        )
    }
    /// A `mutant` line.
    static let mutant = zip(
        lineSession,
        keyIndex,
        choice(of: ResultsLineRenderer.outcomes, known: knownWeight),
        choice(of: ResultsLineRenderer.endings, known: knownWeight),
        flaw
    )
    .map(ResultsLineDraft.MutantDraft.init)

    /// Results files whose headers are all in a format the reader reads.
    static let file = file(lines: line(header: header))
    /// Results files whose headers may be in a newer format, P3.6's input.
    static let anyFile = file(lines: line(header: anyHeader))

    /// A line, its headers from `header`.
    static func line(header: Generator<ResultsLineDraft.HeaderDraft, AnySequence<Any>>)
        -> Generator<ResultsLineDraft, AnySequence<Any>> {
        Gen.frequency(
            (headerWeight, header.map(ResultsLineDraft.header)),
            (mutantWeight, mutant.map(ResultsLineDraft.mutant)),
            (retiredWeight, zip(lineSession, keyIndex.array(of: retiredKeys), flaw)
                .map { session, keys, flaw in ResultsLineDraft.retired(session: session, keys: keys, flaw: flaw) }),
            (kindWeight, zip(lineSession, flaw)
                .map { session, flaw in ResultsLineDraft.control(session: session, flaw: flaw) }),
            (kindWeight, zip(lineSession, choice(of: ResultsLineRenderer.endReasons, known: knownReasonWeight), flaw)
                .map { session, reason, flaw in ResultsLineDraft.end(session: session, reason: reason, flaw: flaw) }),
            (kindWeight, flaw.map(ResultsLineDraft.stopped)),
            (kindWeight, Gen<Int>.value(in: ResultsLineRenderer.unknownKinds.indices).map(ResultsLineDraft.unknown)),
            (kindWeight, Gen<Int>.value(in: ResultsLineRenderer.garbage.indices).map(ResultsLineDraft.garbage)),
            (kindWeight, Gen.always(ResultsLineDraft.blank))
        )
        .eraseToAny()
    }

    /// Results files of `lines`, most after a leading header, some with no
    /// header at all.
    static func file(lines: Generator<ResultsLineDraft, AnySequence<Any>>)
        -> Generator<GeneratedResultsFile, AnySequence<Any>> {
        zip(
            leadHeader.optional(valueRate: leadRate),
            lines.array(of: lineCount),
            MutantKeyGen.key.array(of: drawnKeyCount),
            Gen.bool(crlfRate),
            Gen.bool(finalBreakRate),
            Gen.bool(headerlessRate)
        )
        .map { lead, lines, drawn, crlf, finalBreak, headerless in
            let leading = lead.map { [ResultsLineDraft.header($0)] } ?? []
            let drafts = headerless ? lines.map(withoutHeader) : leading + lines
            return GeneratedResultsFile(draft: ResultsFileDraft(
                lines: drafts.enumerated().map { ResultsFileDraft.Line(tag: $0.offset, draft: $0.element) },
                keys: fixedKeys + drawn,
                crlf: crlf,
                finalBreak: finalBreak
            ))
        }
        .eraseToAny()
    }

    /// The key at `operatorID`'s place in the library file, with
    /// `occurrence`.
    static func libraryKey(_ operatorID: String, occurrence: Int) -> MutantKey {
        MutantKey(
            path: ResultsLineRenderer.libraryPath,
            operatorID: operatorID,
            line: libraryLine,
            column: libraryColumn,
            occurrence: occurrence
        )
    }

    /// The fixed key in the accented file, its path spelled `path`.
    static func cafeKey(_ path: String) -> MutantKey {
        MutantKey(path: path, operatorID: "ReplaceReturnValue", line: cafeLine, column: cafeColumn, occurrence: 0)
    }

    /// `line`, or a `stopped` line with its flaw when it is a header.
    static func withoutHeader(_ line: ResultsLineDraft) -> ResultsLineDraft {
        guard case let .header(header) = line else {
            return line
        }
        return .stopped(header.flaw)
    }

    /// An index into `list`: a value SwiftMutator writes with weight
    /// `known`, else the list's last.
    static func choice(of list: [String], known: Double) -> Generator<Int, AnySequence<Any>> {
        Gen.frequency(
            (known, Gen<Int>.value(in: list.indices.dropLast())),
            (kindWeight, Gen.always(list.count - 1))
        )
        .eraseToAny()
    }

    /// A flaw kind: intact with weight `intact`, else one of the others,
    /// all together with weight 1.
    static func flawKind(intact: Double) -> Generator<ResultsLineDraft.FlawKind, AnySequence<Any>> {
        Gen.frequency(
            (intact, Gen.always(ResultsLineDraft.FlawKind.intact)),
            (flawWeight, Pick.element(of: ResultsLineDraft.FlawKind.allCases.filter { $0 != .intact }))
        )
        .eraseToAny()
    }
}
