//
//  MarkdownCarry.swift
//  SwiftStatsCore
//
//  How M7's report sections (design §10.1) state a collector's status:
//  its state and reason, with the date of a same-tree carry taken apart
//  from the reason the carried run gave, so a carried status reads as the
//  run it was plus when its results were collected.
//

/// A collector's status as M7's report sections state it.
enum MarkdownCarry {
    /// What separates a carry's date from the carried run's own reason.
    private static let separator = "; "

    /// `status` as a section states it: `ran`, or the state with its
    /// reason, the carry's date left out; `not in this snapshot` without
    /// a status.
    static func state(_ status: CollectorStatus?) -> String {
        guard let status else {
            return "not in this snapshot"
        }
        let note = split(status.reason).note
        guard status.state == .ran else {
            return status.state.rawValue + (note.map { ", \($0)" } ?? "")
        }
        return note.map { "ran, \($0)" } ?? "ran"
    }

    /// When `status`'s results were collected, if it carries them from an
    /// earlier scan of the same tree; nil otherwise.
    static func carried(_ status: CollectorStatus?) -> String? {
        split(status?.reason).carried
    }

    /// `reason` with a carry's date taken apart: the date, and the
    /// reason the run gave, nil when it gave none.
    private static func split(_ reason: String?) -> (note: String?, carried: String?) {
        guard let text = reason, text.hasPrefix(CollectorRunInfo.carriedPrefix) else {
            return (reason, nil)
        }
        let parts = String(text.dropFirst(CollectorRunInfo.carriedPrefix.count)).components(separatedBy: separator)
        let rest = parts.dropFirst().joined(separator: separator)
        return (rest.isEmpty ? nil : rest, parts.first)
    }
}
