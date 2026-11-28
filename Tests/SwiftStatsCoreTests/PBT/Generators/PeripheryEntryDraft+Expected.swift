//
//  PeripheryEntryDraft+Expected.swift
//  SwiftStatsCoreTests
//
//  What reading a `PeripheryEntryDraft` should give, from the reader's
//  documented order (`PeripheryOutput`'s header and the doc comment of
//  `fields(of:ordinal:run:)`, design C33): an entry that isn't an object
//  fails; then each of the nine keys, in order, must be present and of its
//  type, a list of strings or a string; then the `hints` list must hold
//  exactly one hint; then the location must read as `path:line:column`
//  (`LocationDraft.expected`). The first fault is named, with the entry's
//  ordinal and run, in the reader's words; an entry with none reads as its
//  strings, lists and location. Keys the reader doesn't read change
//  nothing.
//

@testable import SwiftStatsCore

/// What reading an outskirts entry draft should give.
extension PeripheryEntryDraft {
    /// What reading the entry should give.
    enum Expected: Equatable, Sendable {
        /// These string and list fields, and this location.
        case accepted(strings: [String: String], lists: [String: [String]], location: PeripheryFields.Location)
        /// A `PeripheryOutput.FormatFailure` with exactly this reason.
        case refused(String)
    }

    /// What reading the entry should give: the reason for its first fault,
    /// or its fields.
    var expected: Expected {
        if let first = faults.first {
            return .refused(first)
        }
        var strings: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var read = PeripheryFields.Location(path: "", line: 0, column: 0)
        for (key, field) in zip(Self.keys, fields) {
            switch field {
            case .list(let values):
                lists[key] = values

            case .location(let draft):
                strings[key] = draft.rendered
                read = draft.expected ?? read

            case .string(let value):
                strings[key] = value

            case .missing, .wrong:
                break
            }
        }
        return .accepted(strings: strings, lists: lists, location: read)
    }

    /// Where the reader says a fault lies.
    var place: String {
        "in entry \(ordinal) of the \(run.rawValue) run"
    }

    /// The reason for each fault the entry has, in the order the reader
    /// checks them: only that it isn't an object when it isn't one; else
    /// each key missing or of another type, then a `hints` list without
    /// one hint, then a location that doesn't read.
    var faults: [String] {
        guard notObject == nil else {
            return ["JSON has an entry that isn't an object \(place)"]
        }
        var reasons: [String] = []
        for (key, field) in zip(Self.keys, fields) {
            switch field {
            case .missing:
                reasons.append("JSON lacks \"\(key)\" \(place)")

            case .wrong:
                let type = Self.listKeys.contains(key) ? "a list of strings" : "a string"
                reasons.append("JSON's \"\(key)\" isn't \(type) \(place)")

            case .list, .location, .string:
                break
            }
        }
        if let hintCount, hintCount != 1 {
            reasons.append("JSON's \"hints\" holds \(hintCount) hints, not one, \(place)")
        }
        if let location, location.expected == nil {
            reasons.append("JSON's \"location\" isn't path:line:column \(place)")
        }
        return reasons
    }

    /// How many hints the `hints` list holds, when the key holds one.
    var hintCount: Int? {
        guard case .list(let values) = field("hints") else {
            return nil
        }
        return values.count
    }

    /// The location, when the key holds one.
    var location: LocationDraft? {
        guard case .location(let draft) = field("location") else {
            return nil
        }
        return draft
    }

    /// The key faults, in order: each key missing or of another type.
    var keyFaults: [(key: String, field: Field)] {
        zip(Self.keys, fields).filter { _, field in
            switch field {
            case .missing, .wrong:
                return true

            case .list, .location, .string:
                return false
            }
        }
        .map { (key: $0.0, field: $0.1) }
    }

    /// What `key` holds.
    func field(_ key: String) -> Field? {
        Self.keys.firstIndex(of: key).map { fields[$0] }
    }
}
