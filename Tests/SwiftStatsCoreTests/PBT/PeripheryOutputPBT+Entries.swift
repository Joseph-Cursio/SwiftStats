//
//  PeripheryOutputPBT+Entries.swift
//  SwiftStatsCoreTests
//
//  P9.2's examples, each calling its shared check: the recorded runs'
//  entries, the reader's fault order on hand-written entries, near misses
//  of the nine keys, a padded location, and signed and zero lines and
//  columns; and the meta-tests feeding planted defects' readings to the
//  check.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// P9.2's examples and planted defects.
extension PeripheryOutputPBT {
    @Test("every entry of the recorded runs reads as its values, its location split at its last two colons")
    func recordedEntriesRead() throws {
        let entries = try Self.recordedEntries()

        #expect(entries.count == 26)
        for (offset, element) in entries.enumerated() {
            let object = element as? [String: Any] ?? [:]
            let text = object["location"] as? String ?? ""
            let numbers = text.split(separator: ":").suffix(2).compactMap { Int($0) }
            let path = text.split(separator: ":").dropLast(2).joined(separator: ":")
            let location = PeripheryFields.Location(
                path: path,
                line: numbers.first ?? 0,
                column: numbers.last ?? 0
            )
            let strings = ["accessibility", "kind", "location", "name"].reduce(into: [String: String]()) { found, key in
                found[key] = object[key] as? String
            }
            let lists = ["attributes", "hints", "ids", "modifiers", "modules"]
                .reduce(into: [String: [String]]()) { found, key in
                    found[key] = object[key] as? [String]
                }
            let read = Read { try PeripheryOutput.fields(of: element, ordinal: offset + 1, run: .production) }

            #expect(Self.checkFields(.accepted(strings: strings, lists: lists, location: location), read: read))
        }
    }

    @Test("""
        an entry with every key of another type names the first key; with every key sound, a hints list of \
        none and an empty path name the hints; a missing last key comes before the hints and the location
        """)
    func faultOrder() throws {
        let wrong = PeripheryEntryDraft.keys.map { key in (key, PeripheryEntryDraft.Field.wrong(.null)) }
        let allWrong = Self.draft(Dictionary(uniqueKeysWithValues: wrong))
        let empty = LocationDraft(path: "p", line: 1, column: 2, flaw: .emptyPath)
        let hintsFirst = Self.draft(["hints": .list([]), "location": .location(empty)])
        let lastKey = Self.draft(["name": .missing, "hints": .list(["unused", "unused"]), "location": .location(empty)])

        for (draft, reason) in [
            (allWrong, "JSON's \"accessibility\" isn't a string in entry 7 of the roots run"),
            (hintsFirst, "JSON's \"hints\" holds 0 hints, not one, in entry 7 of the roots run"),
            (lastKey, "JSON lacks \"name\" in entry 7 of the roots run")
        ] {
            let element = try #require(PeripheryEntryDraft.element(of: draft.data))
            let read = Read { try PeripheryOutput.fields(of: element, ordinal: draft.ordinal, run: draft.run) }

            #expect(draft.expected == .refused(reason))
            #expect(Self.checkFields(draft.expected, read: read))
        }
    }

    @Test("""
        near misses of the nine keys don't stand in for a missing one, and a location whose line has leading \
        zeros reads as its digits spell it
        """)
    func nearMissesAndPadding() throws {
        let nearMisses = PeripheryEntryDraft(
            notObject: nil,
            fields: Self.draft(["kind": .missing]).fields,
            extras: [
                JSONText.Member(key: "Kind", value: .string("function.free")),
                JSONText.Member(key: "location ", value: .string("a:1:1"))
            ],
            ordinal: Int.max,
            run: .production
        )
        let zeros = LocationDraft(path: "a:b", line: 7, column: 3, flaw: .padded(zeros: 2, inColumn: false))
        let paddedDraft = Self.draft(["location": .location(zeros)])

        for draft in [nearMisses, paddedDraft] {
            let element = try #require(PeripheryEntryDraft.element(of: draft.data))
            let read = Read { try PeripheryOutput.fields(of: element, ordinal: draft.ordinal, run: draft.run) }

            #expect(Self.checkFields(draft.expected, read: read))
        }
        #expect(nearMisses.expected
            == .refused("JSON lacks \"kind\" in entry 9223372036854775807 of the production run"))
        #expect(zeros.rendered == "a:b:007:3")
    }

    @Test("""
        a location whose line or column carries a plus sign, which Int(_:) alone would parse, or is 0 doesn't \
        read, and the entry names its location
        """)
    func signedAndZeroRefused() throws {
        let flaws: [LocationDraft.Flaw] = [
            .number(.signed, inColumn: false), .number(.signed, inColumn: true), .number(.zero, inColumn: false)
        ]
        let locations = flaws.map { flaw in LocationDraft(path: "a:b", line: 12, column: 3, flaw: flaw) }

        for location in locations {
            let draft = Self.draft(["location": .location(location)])
            let element = try #require(PeripheryEntryDraft.element(of: draft.data))
            let read = Read { try PeripheryOutput.fields(of: element, ordinal: draft.ordinal, run: draft.run) }

            #expect(PeripheryFields.Location(location.rendered) == nil)
            #expect(draft.expected
                == .refused("JSON's \"location\" isn't path:line:column in entry 7 of the roots run"))
            #expect(Self.checkFields(draft.expected, read: read))
        }
        #expect(locations.map(\.rendered) == ["a:b:+12:3", "a:b:12:+3", "a:b:0:3"])
    }

    @Test("a planted defect's reading fails P9.2's law")
    func entryDefectsDetected() throws {
        let twoKeys = Self.draft(["accessibility": .missing, "name": .wrong(.number("3"))])
        let keyAndHints = Self.draft(["ids": .missing, "hints": .list([])])
        let zero = LocationDraft(path: "a", line: 5, column: 6, flaw: .number(.zero, inColumn: false))
        let hintsAndLocation = Self.draft(["hints": .list([]), "location": .location(zero)])
        let mixed = Self.draft(["ids": .wrong(.array([.string("a"), .number("1")]))])
        let place = "in entry 7 of the roots run"
        let element = try #require(PeripheryEntryDraft.element(of: Self.draft([:]).data))
        let sound = try PeripheryOutput.fields(of: element, ordinal: 7, run: .roots)
        var mixedRead = sound
        mixedRead.lists["ids"] = ["a"]

        #expect(Self.checkFields(Self.draft([:]).expected, read: .success(sound)))
        PlantedDefect.expectDetected("the last faulty key named", sourceLocation: #_sourceLocation) {
            Self.checkFields(
                twoKeys.expected,
                read: .failure(PeripheryOutput.FormatFailure(description: "JSON's \"name\" isn't a string \(place)"))
            )
        }
        PlantedDefect.expectDetected("the hints counted before the keys", sourceLocation: #_sourceLocation) {
            Self.checkFields(
                keyAndHints.expected,
                read: .failure(PeripheryOutput.FormatFailure(
                    description: "JSON's \"hints\" holds 0 hints, not one, \(place)"
                ))
            )
        }
        PlantedDefect.expectDetected("the location read before the hints", sourceLocation: #_sourceLocation) {
            Self.checkFields(
                hintsAndLocation.expected,
                read: .failure(PeripheryOutput.FormatFailure(
                    description: "JSON's \"location\" isn't path:line:column \(place)"
                ))
            )
        }
        PlantedDefect.expectDetected("a list holding a number read", sourceLocation: #_sourceLocation) {
            Self.checkFields(mixed.expected, read: .success(mixedRead))
        }
        PlantedDefect.expectDetected("another error thrown", sourceLocation: #_sourceLocation) {
            Self.checkFields(twoKeys.expected, read: .failure(CocoaError(.propertyListReadCorrupt)))
        }
    }

    @Test("a planted defect's reading of a location whose line is 0 or signed fails P9.2's law")
    func locationDefectsDetected() throws {
        let element = try #require(PeripheryEntryDraft.element(of: Self.draft([:]).data))
        let sound = try PeripheryOutput.fields(of: element, ordinal: 7, run: .roots)
        let misreadings: [(defect: String, flaw: LocationDraft.NumberFlaw)] = [
            ("line 0 read", .zero),
            ("a signed line read", .signed)
        ]

        for misreading in misreadings {
            let location = LocationDraft(path: "a", line: 5, column: 6, flaw: .number(misreading.flaw, inColumn: false))
            let draft = Self.draft(["location": .location(location)])
            var read = sound
            read.strings["location"] = location.rendered
            read.location = PeripheryFields.Location(path: "a", line: misreading.flaw == .zero ? 0 : 5, column: 6)

            PlantedDefect.expectDetected(misreading.defect, sourceLocation: #_sourceLocation) {
                Self.checkFields(draft.expected, read: .success(read))
            }
        }
    }
}
