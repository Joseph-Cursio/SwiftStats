//
//  BuildOutputPBT+Mapping.swift
//  SwiftStatsCoreTests
//
//  P1.1's mapping laws: the entries a generated output reads as are mapped
//  onto a measured one-file package, as read (the recordings' root token
//  standing for its root) and moved into its file at their line and column
//  taken modulo its size, so placement, sums and rounding run on its
//  records, and every time is accounted for: each kind's entries counted,
//  the synthesized ones with their time, none dropped, and the totals
//  adding each placed function-body time once, rounded half up.
//

@testable import SwiftStatsCore
import Testing

/// P1.1's package and mapping laws.
extension BuildOutputPBT {
    /// Entries and what a timing mapper made of them.
    struct MappedEntries {
        /// The entries mapped.
        let entries: [TimingEntry]
        /// What mapping them gave.
        let mapped: TimingMapper.Mapped
    }

    /// Hundredths of a millisecond in one.
    static let hundredthsPerMillisecond = 100
    /// Half a millisecond in hundredths, where rounding goes up.
    static let halfMillisecond = 50
    /// The file of the package P1.1 maps entries onto.
    static let libraryFile = "Sources/Lib/Lib.swift"
    /// The package's one file: top-level functions and a type with a
    /// stored property and a method, and no function declared in a body,
    /// so the totals count every function-body entry placed in it.
    static let librarySource = """
        public func first() -> Int { 1 }
        public struct Box {
            public var stored = 1
            public func doubled() -> Int {
                stored * 2
            }
        }
        public func last() -> Int {
            first() + Box().doubled()
        }

        """
    /// The lines an entry moved into the package's file lands on, taken
    /// modulo: line 0, each of its nine lines, and one past its end.
    static let movedLines = 11
    /// The columns an entry moved into the file lands on, taken modulo:
    /// column 0 to two past its longest line's last.
    static let movedColumns = 37
    /// What P1.1's tally counts when the moved entries reach a record.
    static let onRecord = "an entry on a record"
    /// What P1.1's tally counts when they reach a type or the file.
    static let onAttachment = "an entry on a type or the file"
    /// What P1.1's tally counts when an entry has no place.
    static let onNothing = "a synthesized entry"
    /// The placements the mapping laws quantify over, each of which P1.1
    /// must reach at least once (design D14: refused only when one never
    /// fires; each fires in most runs, so 100 runs never miss one).
    static let placements = [onRecord, onAttachment, onNothing]

    /// Whether mapping `given.entries` gave what it must for any entries:
    /// the totals count each kind's entries, and the synthesized entries
    /// (no place) are counted with their time summed and rounded to whole
    /// milliseconds once, half up. Records an issue for each law that
    /// fails.
    static func checkMapping(_ given: MappedEntries, subject: String) -> Bool {
        let synthesized = given.entries.filter { $0.place == nil }
        let synthesizedCount = BuildEntryCount(
            entries: synthesized.count,
            milliseconds: halfUpMilliseconds(synthesized.map(\.hundredths))
        )
        let totals = given.mapped.totals
        return holds(
            [
                (totals.functionEntries == given.entries.count { $0.kind == .function }, "counts every function entry"),
                (totals.expressionEntries == given.entries.count { $0.kind == .expression }, "counts every expression"),
                (given.mapped.unmapped.synthesized == synthesizedCount, "counts the synthesized entries and their time")
            ],
            subject: subject
        )
    }

    /// Whether mapping `given.entries`, all of them in the package's file
    /// or synthesized, placed every entry with a place: none dropped or in
    /// a macro buffer, and the totals adding each placed function-body
    /// entry's time exactly once (no record in the file is nested in a
    /// body), rounded half up. Records an issue for each law that fails.
    static func checkPlaced(_ given: MappedEntries, subject: String) -> Bool {
        let placed = given.entries.filter { $0.place != nil && $0.kind == .function }.map(\.hundredths)
        let none = BuildEntryCount(entries: 0, milliseconds: 0)
        let dropped = given.mapped.dropped
        let left = [dropped.build, dropped.outsideRoot, dropped.fileChanged, dropped.unscanned]
        return holds(
            [
                (left.allSatisfy { $0 == none }, "drops no entry"),
                (given.mapped.unmapped.macro == none, "leaves no entry in a macro buffer"),
                (given.mapped.counted.values.reduce(0, +) == placed.reduce(0, +), "counts each placed time once"),
                (given.mapped.totals.milliseconds == halfUpMilliseconds(placed), "totals the placed functions' time")
            ],
            subject: subject
        )
    }

    /// Counts in `tally` each placement `mapped` reached: a record, a type
    /// or the file, and none.
    static func tally(_ mapped: TimingMapper.Mapped, in tally: AntecedentTally) {
        if mapped.records.isEmpty == false {
            tally.fire(onRecord)
        }
        if mapped.attachments.isEmpty == false {
            tally.fire(onAttachment)
        }
        if mapped.unmapped.synthesized.entries > 0 {
            tally.fire(onNothing)
        }
    }

    /// The sum of `hundredths` in whole milliseconds, half up. Sums of
    /// generated times stay far below what an `Int` holds: at most 40
    /// lines of under 10^14 hundredths each.
    static func halfUpMilliseconds(_ hundredths: [Int]) -> Int {
        (hundredths.reduce(0, +) + halfMillisecond) / hundredthsPerMillisecond
    }

    /// `entries` with each place's recordings' root token (`@ROOT@`)
    /// replaced by `root`.
    static func rooted(_ entries: [TimingEntry], at root: String) -> [TimingEntry] {
        entries.map { entry in
            guard let place = entry.place, place.path.hasPrefix(BuildOutputGen.recordedRoot) else {
                return entry
            }
            let path = root + place.path.dropFirst(BuildOutputGen.recordedRoot.count)
            return TimingEntry(
                kind: entry.kind,
                hundredths: entry.hundredths,
                place: BuildPlace(path: path, line: place.line, column: place.column),
                declaration: entry.declaration
            )
        }
    }

    /// `entries` with each place moved into the package's file under
    /// `root`, its line and column taken modulo `movedLines` and
    /// `movedColumns`, so they land before, on and past its records.
    static func moved(_ entries: [TimingEntry], into root: String) -> [TimingEntry] {
        entries.map { entry in
            guard let place = entry.place else {
                return entry
            }
            return TimingEntry(
                kind: entry.kind,
                hundredths: entry.hundredths,
                place: BuildPlace(
                    path: root + "/" + libraryFile,
                    line: place.line % movedLines,
                    column: place.column % movedColumns
                ),
                declaration: entry.declaration
            )
        }
    }

    /// The package P1.1 maps entries onto, measured; nil, with an issue
    /// recorded, when a record in it is nested in a body, which the
    /// totals law assumes none is.
    static func library() throws -> TimingFigureTests.Library? {
        let library = try TimingFigureTests.Library(TemporaryPackage([libraryFile: librarySource]))
        guard TimingMapper.nestedInBody(library.measured.records, types: library.measured.types).isEmpty else {
            Issue.record("a record of P1.1's package is nested in a body")
            library.package.remove()
            return nil
        }
        return library
    }
}
