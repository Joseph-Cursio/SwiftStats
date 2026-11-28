//
//  PeripheryOutputPBT+Places.swift
//  SwiftStatsCoreTests
//
//  P9.4: a location renders and reads back from the right, its path
//  holding colons, spaces, digits after a colon or a Prepend scalar at its
//  end, and a hint written `name(text)` with a name of ASCII letters
//  splits back into that name and text, whatever the text holds; any
//  other hint reads as `HintPattern`, the checker's pattern, says. Each is
//  asserted on `PeripheryFields.Location`, `PeripheryOutput.split(_:)` and
//  `PeripheryOutput.fields(of:ordinal:run:)` over the entry holding them.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P9.4.
extension PeripheryOutputPBT {
    /// P9.4's base runs, over the engine's 100: one entry costs tens of
    /// microseconds, and the rarest antecedent, a path ending in digits
    /// after a colon, comes in 48 of the meta-test's 1,000 places (design
    /// D14: `(1 - 0.048)^300`, about 4 * 10^-7, is the most a run misses
    /// it; 100 runs would miss it about 7 * 10^-3 of the time).
    static let placeRuns = 300
    /// What P9.4's tally counts when a path holds a colon.
    static let pathColon = "a path holding a colon"
    /// What it counts when a path holds a space.
    static let pathSpace = "a path holding a space"
    /// What it counts when a path ends in a Prepend scalar.
    static let pathPrepend = "a path ending in a Prepend scalar"
    /// What it counts when a path ends in digits after a colon, as a place
    /// does.
    static let pathLikePlace = "a path ending in digits after a colon"
    /// What it counts when the line or the column is `Int.max`.
    static let largestNumber = "the largest line or column"
    /// What it counts when a hint splits.
    static let splits = "a hint that splits"
    /// What it counts when a hint with both parentheses reads whole.
    static let wholeWithParentheses = "a hint with both parentheses that reads whole"
    /// What it counts when split text starts with a combining mark.
    static let markFirst = "split text starting with a combining mark"
    /// What it counts when split text ends in a Prepend scalar.
    static let prependLast = "split text ending in a Prepend scalar"
    /// What it counts when split text holds a parenthesis.
    static let parenthesisInside = "split text holding a parenthesis"
    /// The antecedents P9.4 must reach at least once each.
    static let placeAntecedents = [
        pathColon, pathSpace, pathPrepend, pathLikePlace, largestNumber, splits, wholeWithParentheses, markFirst,
        prependLast, parenthesisInside
    ]
    /// The Prepend scalars the generators draw.
    static let prependScalars = Set(UnicodeGen.prepend.joined().unicodeScalars)
    /// The combining marks the generators draw first in a hint's text.
    static let marks: Set<Unicode.Scalar> = ["\u{301}", "\u{308}"]

    /// The classes `place` falls in, for P9.4's tally and the generator's
    /// meta-test.
    static func placeLabels(of place: PeripheryPlace) -> [String] {
        let path = place.location.path.unicodeScalars
        let parts = path.split(separator: ":", omittingEmptySubsequences: false)
        let digits = parts.last.map { last in last.isEmpty == false && last.allSatisfy { ("0"..."9").contains($0) } }
        let expected = place.hint.expected
        let text = expected.text?.unicodeScalars
        let rendered = place.hint.rendered.unicodeScalars
        return [
            (path.contains(":"), pathColon),
            (path.contains(" "), pathSpace),
            (path.last.map(prependScalars.contains) == true, pathPrepend),
            (parts.count > 1 && digits == true, pathLikePlace),
            (place.location.line == Int.max || place.location.column == Int.max, largestNumber),
            (text != nil, splits),
            (text == nil && rendered.contains("(") && rendered.last == ")", wholeWithParentheses),
            (text?.first.map(marks.contains) == true, markFirst),
            (text?.last.map(prependScalars.contains) == true, prependLast),
            (text.map { $0.contains("(") || $0.contains(")") } == true, parenthesisInside)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `read`, `split` and `fields`, what reading `place`'s
    /// location, splitting its hint and reading the entry holding them
    /// gave, are the location drafted, the name and text the hint should
    /// split into, and that entry's location and hint, scalar for scalar.
    /// Records an issue for each law that fails.
    static func checkPlace(
        _ place: PeripheryPlace,
        read: PeripheryFields.Location?,
        split: (name: String, text: String?),
        fields: Read
    ) -> Bool {
        let location = place.location.expected
        let expected = place.hint.expected
        var laws = [
            (same(read, location), "reads \(shown(read)), expected \(shown(location))"),
            (
                sameScalars(split.name, expected.name) && sameScalars(split.text, expected.text),
                "splits the hint as \(split.name.debugDescription) and \(split.text.debugDescription), expected "
                    + "\(expected.name.debugDescription) and \(expected.text.debugDescription)"
            )
        ]
        switch fields {
        case .success(let entry):
            let hints = entry.lists["hints"] ?? []
            laws.append((
                same(entry.location, location),
                "reads the entry's location as \(shown(entry.location)), expected \(shown(location))"
            ))
            laws.append((
                hints.count == 1 && sameScalars(hints.first, place.hint.rendered),
                "reads the entry's hints as \(hints), expected one, \(place.hint.rendered.debugDescription)"
            ))

        case .failure(let error):
            laws.append((false, "fails to read the entry: \(error)"))
        }
        return holds(laws, subject: "the place")
    }

    // MARK: P9.4

    /// Invariant: a location renders and reads back from the right as its
    /// path, line and column, its path scalar for scalar, and a hint
    /// written `name(text)` with a name of ASCII letters splits back into
    /// them, any other hint reading as the checker's pattern says; the
    /// entry holding both reads them so.
    /// Why it holds: `PeripheryFields.Location`'s doc comment (read from
    /// the right, its colons among Unicode scalars, design B23 and U13),
    /// `PeripheryOutput.split(_:)`'s doc comment and the header (`name(text)`,
    /// the name ASCII letters, its parentheses among scalars), and
    /// `Scripts/index-check.py`'s `HINT_WITH_TEXT`, which the reference
    /// `HintPattern` follows.
    /// Why it might not: the path isn't empty and the line and column are
    /// 1 to `Int.max` (the doc comment's domain); text is any scalars, the
    /// surrogates excluded (a `String` can't hold one); no text starts with
    /// U+FEFF (assumed: `JSONSerialization` drops it, B29 awaiting U17,
    /// pinned in `PeripheryOutputTests+Scalars`).
    /// Oracle: round trip, and `HintPattern` for hints not written
    /// `name(text)`; planted defects: the path split at its first colon,
    /// the colons found among Characters, the hint split on Characters
    /// (B23's hint fix undone), a name holding a digit split, and the
    /// text's last scalar dropped, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        a location reads back from the right, and a hint written name(text) with a name of ASCII letters \
        splits back, any other reading whole
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func placesReadBack() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.placeRuns), input: PeripheryJSONGen.place) { place in
            PBTTrace.note(place)
            Self.placeLabels(of: place).forEach(tally.fire)
            guard let element = PeripheryEntryDraft.element(of: place.data) else {
                PBTTrace.firstFailure(place, latch: latch)
                return
            }
            let read = PeripheryFields.Location(place.location.rendered)
            let split = PeripheryOutput.split(place.hint.rendered)
            let fields = Read { try PeripheryOutput.fields(of: element, ordinal: 1, run: .roots) }
            if Self.checkPlace(place, read: read, split: split, fields: fields) == false {
                PBTTrace.firstFailure(place, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.placeAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        every recorded location reads back, its path split at its last two colons, and each recorded hint \
        and outskirts' redundantConformance hint split back
        """)
    func recordedPlacesReadBack() throws {
        let entries = try Self.recordedEntries()
        let conformance = HintDraft(
            name: "redundantConformance",
            opens: true,
            text: "replace with: 'A, B'",
            closes: true
        )

        #expect(entries.count == 26)
        for element in entries {
            let object = element as? [String: Any] ?? [:]
            let text = object["location"] as? String ?? ""
            let numbers = text.split(separator: ":").suffix(2).compactMap { Int($0) }
            let location = LocationDraft(
                path: text.split(separator: ":").dropLast(2).joined(separator: ":"),
                line: numbers.first ?? 0,
                column: numbers.last ?? 0,
                flaw: .sound
            )
            let hint = (object["hints"] as? [String])?.first ?? ""
            for draft in [HintDraft(name: hint, opens: false, text: "", closes: false), conformance] {
                let place = PeripheryPlace(location: location, hint: draft)
                let entry = try #require(PeripheryEntryDraft.element(of: place.data))
                let read = PeripheryFields.Location(place.location.rendered)
                let split = PeripheryOutput.split(place.hint.rendered)
                let fields = Read { try PeripheryOutput.fields(of: entry, ordinal: 1, run: .roots) }

                #expect(location.rendered == text)
                #expect(Self.checkPlace(place, read: read, split: split, fields: fields))
            }
        }
    }

    @Test("""
        a location at the domain's edges reads back: a path with spaces, colons and digits after one, ending \
        in a Prepend scalar, the largest line; and text starting with a mark and ending in a Prepend scalar \
        splits back
        """)
    func edgePlaceReadsBack() throws {
        let location = LocationDraft(
            path: "/NoSuchPeripheryPackage/My Sources/a:b c.swift:12\u{6DD}",
            line: Int.max,
            column: 1,
            flaw: .sound
        )
        let hint = HintDraft(
            name: "redundantConformance",
            opens: true,
            text: "\u{301}with: 'A, (B)'\u{600}",
            closes: true
        )
        let place = PeripheryPlace(location: location, hint: hint)
        let entry = try #require(PeripheryEntryDraft.element(of: place.data))

        let read = PeripheryFields.Location(place.location.rendered)
        let split = PeripheryOutput.split(place.hint.rendered)
        let fields = Read { try PeripheryOutput.fields(of: entry, ordinal: 1, run: .roots) }

        #expect(Self.checkPlace(place, read: read, split: split, fields: fields))
        #expect(location.rendered.hasSuffix("12\u{6DD}:9223372036854775807:1"))
    }

    @Test("""
        a hint whose name isn't plain letters reads whole, even with both parentheses, and one whose name is \
        followed by a parenthesis inside a word splits at the first
        """)
    func oddHintsReadWhole() throws {
        let location = LocationDraft(path: "a", line: 1, column: 1, flaw: .sound)
        let hints = ["a1", "", "\u{E9}t\u{E9}", "a b", "a(b"].map { name in
            HintDraft(name: name, opens: true, text: "x", closes: true)
        }

        for hint in hints {
            let place = PeripheryPlace(location: location, hint: hint)
            let entry = try #require(PeripheryEntryDraft.element(of: place.data))
            let read = PeripheryFields.Location(place.location.rendered)
            let split = PeripheryOutput.split(place.hint.rendered)
            let fields = Read { try PeripheryOutput.fields(of: entry, ordinal: 1, run: .roots) }

            #expect(Self.checkPlace(place, read: read, split: split, fields: fields))
        }
        #expect(hints.map(\.expected.text) == [nil, nil, nil, nil, "b(x"])
    }

    @Test("a planted defect's reading fails P9.4's law")
    func placeDefectsDetected() throws {
        let colons = PeripheryPlace(
            location: LocationDraft(path: "a:b\u{600}", line: 12, column: 9, flaw: .sound),
            hint: HintDraft(name: "unused", opens: true, text: "\u{301}x\u{6DD}", closes: true)
        )
        let digits = PeripheryPlace(
            location: colons.location,
            hint: HintDraft(name: "a1", opens: true, text: "x", closes: true)
        )
        let entry = try #require(PeripheryEntryDraft.element(of: colons.data))
        let fields = Read { try PeripheryOutput.fields(of: entry, ordinal: 1, run: .roots) }
        let digitEntry = try #require(PeripheryEntryDraft.element(of: digits.data))
        let digitFields = Read { try PeripheryOutput.fields(of: digitEntry, ordinal: 1, run: .roots) }
        let location = colons.location.expected
        let split = PeripheryOutput.split(colons.hint.rendered)
        let firstColon = PeripheryFields.Location(path: "a", line: 12, column: 9)

        #expect(Self.checkPlace(colons, read: location, split: split, fields: fields))
        PlantedDefect.expectDetected("the path split at its first colon", sourceLocation: #_sourceLocation) {
            Self.checkPlace(colons, read: firstColon, split: split, fields: fields)
        }
        PlantedDefect.expectDetected("the colons found among Characters", sourceLocation: #_sourceLocation) {
            Self.checkPlace(colons, read: nil, split: split, fields: fields)
        }
        PlantedDefect.expectDetected("the hint split on Characters", sourceLocation: #_sourceLocation) {
            Self.checkPlace(colons, read: location, split: (colons.hint.rendered, nil), fields: fields)
        }
        PlantedDefect.expectDetected("a name holding a digit split", sourceLocation: #_sourceLocation) {
            Self.checkPlace(digits, read: location, split: ("a1", "x"), fields: digitFields)
        }
        PlantedDefect.expectDetected("the text's last scalar dropped", sourceLocation: #_sourceLocation) {
            Self.checkPlace(colons, read: location, split: ("unused", "\u{301}x"), fields: fields)
        }
    }
}
