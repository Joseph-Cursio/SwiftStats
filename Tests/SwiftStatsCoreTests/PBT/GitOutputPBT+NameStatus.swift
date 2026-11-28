//
//  GitOutputPBT+NameStatus.swift
//  SwiftStatsCoreTests
//
//  P14.2: a rendered `git diff --name-status -z` listing reads, through
//  `MutationWorkCopy.decodedPaths(_:)` and `MutationChanges.changedPaths(_:)`
//  as SwiftMutator's selection reads it, as the last path of every entry
//  that isn't a deletion, in order; a listing cut anywhere gives its whole
//  entries' paths first, then at most one more, a path the cut entry wrote
//  before the cut, and none for a deletion, and never traps; its
//  examples, the listings it shrank B36's failures to (`CorpusEntry`), and
//  meta-tests that feed planted defects' readings to its check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P14.2.
extension GitOutputPBT {
    /// P14.2's base runs, over the engine's 100: decoding and reading a
    /// listing of at most six entries costs a few microseconds. The rarest
    /// antecedent, a listing cut after the first path of a copy or rename,
    /// the one cut that leaves a path of the cut entry to read, comes in
    /// 65 of the meta-test's 1,000 listings (design D14: `(1 - 0.065)^300`,
    /// about 2 * 10^-9, is the most a run misses it; 100 runs would miss it
    /// about 10^-3 of the time).
    static let listingRuns = 300
    /// What P14.2's tally counts when a whole entry is a copy.
    static let wholeCopy = "a whole copy"
    /// What it counts when a whole entry is a rename.
    static let wholeRename = "a whole rename"
    /// What it counts when a whole entry is a deletion.
    static let wholeDeletion = "a whole deletion"
    /// What it counts when a whole entry's path is spelled like a status.
    static let statusLikePath = "a whole entry's path spelled like a status"
    /// What it counts when a path holds a line break or a CR.
    static let breakInPath = "a whole entry's path holding a line break or a CR"
    /// What it counts when a whole entry's path starts with a byte order
    /// mark.
    static let markedPath = "a whole entry's path starting with a byte order mark"
    /// What it counts when a listing is cut between entries.
    static let cutBetween = "a listing cut between entries"
    /// What it counts when a listing is cut just after a status.
    static let cutAfterStatus = "a listing cut just after a status"
    /// What it counts when a listing is cut after a copy's or rename's
    /// first path.
    static let cutAfterFirstPath = "a listing cut after a copy's or rename's first path"
    /// The antecedents P14.2 must reach at least once each.
    static let listingAntecedents = [
        wholeCopy, wholeRename, wholeDeletion, statusLikePath, breakInPath, markedPath, cutBetween, cutAfterStatus,
        cutAfterFirstPath
    ]
    /// Paths spelled like a status.
    static let statusSpellings: Set<String> = ["A", "C050", "D", "M", "R100"]
    /// Listings P14.2 shrank a failure to: its first run's, which found
    /// design B36, and the one it gave with B36's fix taken out.
    static let listingCorpus = [
        CorpusEntry(
            input: NameStatusDraft(entries: [entry(.renamed, 0, ["a.swift", "\u{FEFF}"])], cut: nil),
            pins: "B36: a rename's new path, a byte order mark alone, lost its mark and read as empty"
        ),
        CorpusEntry(
            input: NameStatusDraft(entries: [entry(.added, 0, ["\u{FEFF}"])], cut: nil),
            pins: "B36: an added path, a byte order mark alone, lost its mark and read as empty"
        )
    ]

    /// The classes `draft` falls in, for P14.2's tally and the generator's
    /// meta-test.
    static func listingLabels(of draft: NameStatusDraft) -> [String] {
        let whole = draft.wholeEntries
        let paths = whole.flatMap(\.paths)
        let kept = draft.cutPoint?.kept
        return [
            (whole.contains { $0.status == .copied }, wholeCopy),
            (whole.contains { $0.status == .renamed }, wholeRename),
            (whole.contains { $0.status == .deleted }, wholeDeletion),
            (paths.contains(where: statusSpellings.contains), statusLikePath),
            (paths.contains { $0.unicodeScalars.contains("\n") || $0.unicodeScalars.contains("\r") }, breakInPath),
            (paths.contains { $0.unicodeScalars.first == "\u{FEFF}" }, markedPath),
            (kept == 0, cutBetween),
            (kept == 1, cutAfterStatus),
            ((kept ?? 0) > 1, cutAfterFirstPath)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `listing`, the paths read from `draft`'s listing or the
    /// failure decoding it gave, are the model's: the whole entries' paths
    /// first, scalar for scalar, then at most one more, a path the cut
    /// entry wrote before the cut. Records an issue for each law that
    /// fails.
    static func checkPaths(_ draft: NameStatusDraft, read listing: Listing) -> Bool {
        guard case .success(let read) = listing else {
            return holds([(false, "fails to decode the listing's fields: \(listing)")], subject: "reading the listing")
        }
        let expected = draft.expected
        let first = read.prefix(expected.count).map { Array($0.unicodeScalars) }
        let extra = read.dropFirst(expected.count)
        let allowed = scalars(draft.cutPaths)
        return holds(
            [
                (first == expected.map { Array($0.unicodeScalars) }, "reads \(read), expected \(expected) first"),
                (
                    extra.count <= 1 && extra.allSatisfy { allowed.contains(Array($0.unicodeScalars)) },
                    "reads \(Array(extra)) after them, expected at most one of \(draft.cutPaths)"
                )
            ],
            subject: "reading the listing"
        )
    }

    /// The paths `draft`'s listing reads as, as SwiftMutator's selection
    /// reads git's: its fields decoded, then the paths they name; or the
    /// failure decoding them gave.
    static func readPaths(_ draft: NameStatusDraft) -> Listing {
        Listing { try MutationChanges.changedPaths(MutationWorkCopy.decodedPaths(draft.data)) }
    }

    /// An entry of an example listing, of `status`, `score` and `paths`.
    static func entry(_ status: NameStatusEntry.Status, _ score: Int, _ paths: [String]) -> NameStatusEntry {
        NameStatusEntry(status: status, score: score, paths: paths)
    }

    // MARK: P14.2

    /// Invariant: a rendered `--name-status -z` listing reads as the last
    /// path of every entry that isn't a deletion, in order, scalar for
    /// scalar; one cut anywhere reads as its whole entries' paths, then at
    /// most one more, a path the cut entry wrote before the cut and none
    /// for a deletion, and never traps.
    /// Why it holds: `MutationChanges.changedPaths(_:)`'s doc comment (each
    /// entry's path, the new one of a rename or copy, deletions dropped),
    /// `read(in:since:)`'s (SwiftMutator's selection), `decodedPaths`'s
    /// (each name's bytes as they are, design B36), git's `-z` format (a
    /// status field, then one path, two for `C` and `R`, each NUL-ended and
    /// unquoted), and M6 design §6.1.
    /// Why it might not: no path is empty or holds NUL and every path is
    /// UTF-8, as `decodedPaths` requires and git writes; a cut falls
    /// between fields (a cut inside one makes a different path, which no
    /// reading can tell from a real one); which path of a cut copy or
    /// rename is read, if any, isn't specified, so either is allowed.
    /// Oracle: the generating model (`NameStatusDraft.expected` and
    /// `cutPaths`); planted defects: a copy read as naming one path, a
    /// rename's or copy's first path kept, deletions kept, the status's
    /// last character tested, the status kept at a cut, the cut entry
    /// indexed past the listing's end (a trap), and a leading byte order
    /// mark dropped (B36 undone), each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        a name-status listing reads as the last path of every entry but a deletion, in order, and a cut one as \
        its whole entries' paths and at most one of the cut entry's
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func listingPathsReadBack() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.listingRuns), input: NameStatusGen.listing) { draft in
            PBTTrace.note(draft)
            Self.listingLabels(of: draft).forEach(tally.fire)
            let read = Listing { try MutationChanges.changedPaths(MutationWorkCopy.decodedPaths(draft.data)) }
            if Self.checkPaths(draft, read: read) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.listingAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        SwiftMutator's recorded selection example reads back: a modification, a rename, a deletion and a copy, \
        whole and cut after each field
        """)
    func recordedListingReadsBack() throws {
        let entries = [
            Self.entry(.modified, 0, ["a.swift"]), Self.entry(.renamed, 87, ["old.swift", "new.swift"]),
            Self.entry(.deleted, 0, ["gone.swift"]), Self.entry(.copied, 100, ["x.swift", "y.swift"])
        ]
        let whole = NameStatusDraft(entries: entries, cut: nil)
        let read = Listing { try MutationChanges.changedPaths(MutationWorkCopy.decodedPaths(whole.data)) }

        #expect(whole.fields == [
            "M", "a.swift", "R087", "old.swift", "new.swift", "D", "gone.swift", "C100", "x.swift", "y.swift"
        ])
        #expect(Self.checkPaths(whole, read: read))
        #expect(try read.get() == ["a.swift", "new.swift", "y.swift"])
        for index in entries.indices {
            for kept in entries[index].fields.indices {
                let draft = NameStatusDraft(entries: entries, cut: NameStatusDraft.Cut(entry: index, kept: kept))

                #expect(Self.checkPaths(draft, read: Self.readPaths(draft)))
            }
        }
    }

    @Test("""
        paths spelled like statuses, holding line breaks, a CR or a tab, led by a mark or a byte order mark, and \
        accented both ways, read back scalar for scalar, and an empty listing reads as none
        """)
    func oddPathsReadBack() throws {
        let draft = NameStatusDraft(
            entries: [
                Self.entry(.modified, 0, ["D"]), Self.entry(.renamed, 100, ["R100", "M"]),
                Self.entry(.added, 0, ["x\ny.swift"]), Self.entry(.copied, 0, ["x\ry.swift", "\u{301}a.swift"]),
                Self.entry(.typeChanged, 0, ["Caf\u{E9}.swift"]), Self.entry(.unmerged, 0, ["Cafe\u{301}.swift"]),
                Self.entry(.unknown, 0, ["x\ty.swift"]), Self.entry(.deleted, 0, ["C050"]),
                Self.entry(.added, 0, ["\u{FEFF}b.swift"])
            ],
            cut: nil
        )
        let empty = NameStatusDraft(entries: [], cut: NameStatusDraft.Cut(entry: 3, kept: 1))
        let read = Listing { try MutationChanges.changedPaths(MutationWorkCopy.decodedPaths(draft.data)) }

        #expect(Self.checkPaths(draft, read: read))
        #expect(draft.expected == [
            "D", "M", "x\ny.swift", "\u{301}a.swift", "Caf\u{E9}.swift", "Cafe\u{301}.swift", "x\ty.swift",
            "\u{FEFF}b.swift"
        ])
        #expect(Self.checkPaths(empty, read: Self.readPaths(empty)))
        #expect(try Self.readPaths(empty).get().isEmpty)
    }

    @Test("B36: a listing P14.2 shrank a failure to reads back, its byte order mark kept", arguments: listingCorpus)
    func listingCorpusReadsBack(entry: CorpusEntry<NameStatusDraft>) throws {
        let read = Listing { try MutationChanges.changedPaths(MutationWorkCopy.decodedPaths(entry.input.data)) }

        #expect(Self.checkPaths(entry.input, read: read))
        #expect(try read.get().map { Array($0.unicodeScalars) } == [["\u{FEFF}"]])
    }

    @Test("a planted defect's reading fails P14.2's law")
    func listingDefectsDetected() {
        let entries = [
            Self.entry(.modified, 0, ["a.swift"]), Self.entry(.renamed, 87, ["old.swift", "new.swift"]),
            Self.entry(.deleted, 0, ["gone.swift"])
        ]
        let whole = NameStatusDraft(entries: entries, cut: nil)
        let cutAtStatus = NameStatusDraft(entries: entries, cut: NameStatusDraft.Cut(entry: 1, kept: 1))
        let failure = MutationFailure(description: "making the copy failed: git lists paths that aren't UTF-8: 1 of 1")

        #expect(Self.checkPaths(whole, read: .success(["a.swift", "new.swift"])))
        PlantedDefect.expectDetected("a rename's first path kept", sourceLocation: #_sourceLocation) {
            Self.checkPaths(whole, read: .success(["a.swift", "old.swift"]))
        }
        PlantedDefect.expectDetected("deletions kept", sourceLocation: #_sourceLocation) {
            Self.checkPaths(whole, read: .success(["a.swift", "new.swift", "gone.swift"]))
        }
        PlantedDefect.expectDetected("the status kept at a cut", sourceLocation: #_sourceLocation) {
            Self.checkPaths(cutAtStatus, read: .success(["a.swift", "R087"]))
        }
        PlantedDefect.expectDetected("a rename read as naming one path", sourceLocation: #_sourceLocation) {
            // `new.swift` then reads as a status, and `D` as its path.
            Self.checkPaths(whole, read: .success(["a.swift", "old.swift", "D"]))
        }
        PlantedDefect.expectDetected("a leading byte order mark dropped, B36", sourceLocation: #_sourceLocation) {
            let marked = NameStatusDraft(entries: [Self.entry(.modified, 0, ["\u{FEFF}a.swift"])], cut: nil)
            return Self.checkPaths(marked, read: .success(["a.swift"]))
        }
        PlantedDefect.expectDetected("the listing left undecoded", sourceLocation: #_sourceLocation) {
            Self.checkPaths(whole, read: .failure(failure))
        }
    }
}
