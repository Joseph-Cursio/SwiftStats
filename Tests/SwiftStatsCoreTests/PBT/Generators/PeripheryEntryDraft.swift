//
//  PeripheryEntryDraft.swift
//  SwiftStatsCoreTests
//
//  One outskirts entry as decisions, P9.2's input: either a value that
//  isn't an object, or an object holding, for each of the nine keys, a
//  value of the right type, none, or a value of another type (a number, a
//  Boolean, `null`, an object, a string where a list belongs, a list where
//  a string belongs, a list holding something other than a string); the
//  `hints` list holding any number of hints and the location any text a
//  `LocationDraft` writes; keys the reader doesn't read (`asset`, `range`,
//  and near misses of the nine: `Kind`, `location `, `HINTS`); and the
//  entry's ordinal and run. A part may be faulty independently of the
//  others, so an entry may have several faults, of which the reader names
//  the first. The entry is written as a run's JSON array of that one
//  entry, which `JSONSerialization` reads as the collector's does. What
//  reading it should give is in `PeripheryEntryDraft+Expected`.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// One outskirts entry as decisions.
struct PeripheryEntryDraft: Hashable, Sendable, CustomTestStringConvertible {
    /// What one of the nine keys holds.
    enum Field: Hashable, Sendable {
        /// A list of strings.
        case list([String])
        /// A location's text.
        case location(LocationDraft)
        /// Nothing: the key is missing.
        case missing
        /// A string.
        case string(String)
        /// A value of another type than the key's.
        case wrong(JSONText)
    }

    /// The nine keys every entry holds, in the order the reader checks
    /// them (`PeripheryOutput`'s header: `accessibility`, `attributes`,
    /// `hints`, `ids`, `kind`, `location`, `modifiers`, `modules` and
    /// `name`).
    static let keys = [
        "accessibility", "attributes", "hints", "ids", "kind", "location", "modifiers", "modules", "name"
    ]
    /// The keys whose values are lists of strings (design §5.3; the
    /// checker's `OUTSKIRTS_LISTS`); the others hold strings.
    static let listKeys: Set = ["attributes", "hints", "ids", "modifiers", "modules"]

    /// The value the entry is when it isn't an object; nil when it is one.
    let notObject: JSONText?
    /// What each of `keys` holds, in that order.
    let fields: [Field]
    /// Members the reader doesn't read, each key once and none of the nine.
    let extras: [JSONText.Member]
    /// The entry's 1-based place in its run's output.
    let ordinal: Int
    /// Its run.
    let run: DeadCodeRun

    /// The entry as JSON.
    var entry: JSONText {
        if let notObject {
            return notObject
        }
        let members = zip(Self.keys, fields).compactMap { key, field in
            Self.value(of: field).map { JSONText.Member(key: key, value: $0) }
        }
        return .object(members + extras)
    }

    /// The run's output: an array of the one entry.
    var data: Data {
        Self.data(of: entry)
    }

    /// What reading it should give, the ordinal and run, then the entry,
    /// in ASCII (`PBTTrace.ascii`).
    var testDescription: String {
        let outcome: String
        switch expected {
        case .accepted:
            outcome = "read"

        case .refused(let reason):
            outcome = "refused: " + reason
        }
        return PBTTrace.ascii("expected \(outcome); entry \(ordinal) of the \(run.rawValue) run: " + entry.text)
    }

    /// The JSON value `field` writes; nil when the key is missing.
    static func value(of field: Field) -> JSONText? {
        switch field {
        case .list(let values):
            return .array(values.map(JSONText.string))

        case .location(let location):
            return .string(location.rendered)

        case .missing:
            return nil

        case .string(let value):
            return .string(value)

        case .wrong(let value):
            return value
        }
    }

    /// A run's output holding `entry` alone.
    static func data(of entry: JSONText) -> Data {
        Data(JSONText.array([entry]).text.utf8)
    }

    /// The one entry of `data`, a run's output, as `JSONSerialization`
    /// reads it, which is what `PeripheryOutput.decode` hands
    /// `PeripheryOutput.fields(of:ordinal:run:)`; nil, with an issue
    /// recorded, when it doesn't read as an array of one element.
    static func element(of data: Data) -> Any? {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any], array.count == 1 else {
            Issue.record(Comment(rawValue: PBTTrace.ascii("the generated output doesn't read as one entry: "
                + (String(data: data, encoding: .utf8) ?? "not UTF-8"))))
            return nil
        }
        return array[0]
    }
}
