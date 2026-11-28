//
//  NameStatusDraft.swift
//  SwiftStatsCoreTests
//
//  P14.2's input: a `git diff --name-status -z` listing as decisions, its
//  entries and, for a truncated listing, where it is cut: before an entry,
//  just after its status, or after the first path of a copy or rename.
//  The model is the design's sentence: the paths read are the last path of
//  every entry that isn't a deletion, in order; a cut listing gives those
//  of its whole entries first, then at most one more path, one the cut
//  entry wrote before the cut, and none when that entry is a deletion.
//

import Foundation
import Testing

/// A `git diff --name-status -z` listing as decisions.
struct NameStatusDraft: Sendable, CustomTestStringConvertible {
    /// Where a listing is cut.
    struct Cut: Hashable, Sendable {
        /// Which entry the cut falls in, taken modulo the entry count.
        let entry: Int
        /// How many of that entry's fields are kept, taken modulo its field
        /// count, so the entry is never whole.
        let kept: Int
    }

    /// How many digits git writes a score in (forced: `%03d`).
    static let scoreWidth = 3

    /// The entries, in order.
    let entries: [NameStatusEntry]
    /// Where the listing is cut; nil when it is whole.
    let cut: Cut?

    /// The index of the entry the cut falls in, and how many of its fields
    /// are kept; nil for a whole listing.
    var cutPoint: (entry: Int, kept: Int)? {
        guard let cut, entries.isEmpty == false else {
            return nil
        }
        let entry = cut.entry % entries.count
        return (entry, cut.kept % entries[entry].fields.count)
    }

    /// The entries the listing holds whole.
    var wholeEntries: ArraySlice<NameStatusEntry> {
        entries.prefix(cutPoint?.entry ?? entries.count)
    }

    /// The fields of the listing, after the cut is made.
    var fields: [String] {
        let whole = wholeEntries.flatMap(\.fields)
        guard let point = cutPoint else {
            return whole
        }
        return whole + entries[point.entry].fields.prefix(point.kept)
    }

    /// The listing as git writes it: each field and a NUL.
    var data: Data {
        Data(fields.flatMap { Array($0.utf8) + [0] })
    }

    /// The paths the whole entries give: the last path of each that isn't
    /// a deletion, in order.
    var expected: [String] {
        wholeEntries.filter { $0.status != .deleted }.compactMap(\.paths.last)
    }

    /// The paths of the cut entry written before the cut, one of which the
    /// reading may give after `expected`; none when that entry is a
    /// deletion or the listing is whole.
    var cutPaths: [String] {
        guard let point = cutPoint, entries[point.entry].status != .deleted else {
            return []
        }
        return Array(entries[point.entry].paths.prefix(max(0, point.kept - 1)))
    }

    /// The fields, where the cut falls, and what the reading should give,
    /// in ASCII.
    var testDescription: String {
        let place = cutPoint.map { "cut in entry \($0.entry) after \($0.kept) of its fields" } ?? "whole"
        return PBTTrace.ascii(
            "fields \(fields) (\(place)); expected \(expected), then at most one of \(cutPaths)"
        )
    }
}
