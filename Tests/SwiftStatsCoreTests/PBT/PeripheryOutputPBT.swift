import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of reading outskirts' JSON (M7, design §5.3, design
/// §4.1.4): an entry's fields are read exactly when none is missing or of
/// another type, it holds one hint and its location reads, and otherwise
/// the first fault in the reader's order is named with the entry's
/// ordinal and run (P9.2); a location renders and reads back from the
/// right, its path holding colons, spaces or a Prepend scalar, and a hint
/// written `name(text)` with a name of ASCII letters splits back, any
/// other reading whole (P9.4). Both are asserted on
/// `PeripheryOutput.fields(of:ordinal:run:)`, `PeripheryFields.Location`
/// and `PeripheryOutput.split(_:)`, never through `decode`, which calls
/// `realpath(3)`. `PeripheryOutputTests` holds the fixed examples; each
/// property here has its own, calling its shared check, and meta-tests
/// that feed a planted defect's output to that check.
@Suite("outskirts output: properties", .tags(.pbt))
struct PeripheryOutputPBT {
    /// What reading one entry gives.
    typealias Read = Result<PeripheryFields, any Error>

    /// P9.2's base runs, over the engine's 100: rendering and reading one
    /// entry costs tens of microseconds. The rarest antecedent, a line or
    /// column of 0 as the entry's only fault, the one input on which a
    /// reader taking 0 as positive shows, comes in 34 of the meta-test's
    /// 1,000 entries (design D14: `(1 - 0.034)^450`, about 2 * 10^-7, is
    /// the most a run misses it; 300 runs would miss it about 3 * 10^-5 of
    /// the time); a signed line or column as the only fault, the one input
    /// on which a reader skipping the ASCII-digit check shows, comes in 51.
    /// A location read through leading zeros, 18 in 1,000, is tallied but
    /// not required; an example pins it.
    static let entryRuns = 450
    /// What P9.2's tally counts when an entry reads.
    static let reads = "an entry that reads"
    /// What it counts when an entry isn't an object.
    static let notAnObject = "an entry that isn't an object"
    /// What it counts when a key is missing.
    static let missingKey = "a key missing"
    /// What it counts when a string key holds another type.
    static let mistypedString = "a string key of another type"
    /// What it counts when a list key holds a list holding something other
    /// than a string.
    static let mixedList = "a list holding something other than a string"
    /// What it counts when a `hints` list holds other than one hint.
    static let wrongHintCount = "a hints list without one hint"
    /// What it counts when a location doesn't read.
    static let badLocation = "a location that doesn't read"
    /// What it counts when two keys are faulty.
    static let twoKeyFaults = "two keys faulty"
    /// What it counts when a key fault and a hints fault meet.
    static let keyBesideHints = "a key fault beside a hints fault"
    /// What it counts when a key fault and a location fault meet.
    static let keyBesideLocation = "a key fault beside a location fault"
    /// What it counts when a hints fault and a location fault meet, every
    /// key sound.
    static let hintsBesideLocation = "a hints fault beside a location fault, every key sound"
    /// What it counts when a line or column of 0 is an entry's only fault.
    static let zeroAlone = "a line or column of 0, the entry's only fault"
    /// What it counts when a signed line or column is an entry's only
    /// fault.
    static let signedAlone = "a signed line or column, the entry's only fault"
    /// What it counts when an entry that reads has a padded location.
    static let padded = "a location that reads through leading zeros"
    /// The antecedents P9.2 must reach at least once each.
    static let entryAntecedents = [
        reads, notAnObject, missingKey, mistypedString, mixedList, wrongHintCount, badLocation, twoKeyFaults,
        keyBesideHints, keyBesideLocation, hintsBesideLocation, zeroAlone, signedAlone
    ]

    /// The recorded runs: the Index fixture's three outputs.
    static let recordedRuns = ["outskirts-roots.json", "outskirts-stale-roots.json", "outskirts-production.json"]

    /// Each recorded run's entries, as `JSONSerialization` reads them.
    static func recordedEntries() throws -> [Any] {
        try recordedRuns.flatMap { name in
            let data = Data(try IndexFixture.text(name).utf8)
            return try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
        }
    }

    /// Records an issue naming `subject`, in ASCII, for each law in `laws`
    /// that fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record(Comment(rawValue: PBTTrace.ascii("\(subject) fails: it \(law.law)")))
        }
        return laws.allSatisfy(\.holds)
    }

    /// Whether `found` and `expected` are the same location, the path
    /// scalar for scalar.
    static func same(_ found: PeripheryFields.Location?, _ expected: PeripheryFields.Location?) -> Bool {
        found == expected && sameScalars(found?.path, expected?.path)
    }

    /// Whether `found` and `expected` are both nil or hold the same
    /// scalars.
    static func sameScalars(_ found: String?, _ expected: String?) -> Bool {
        switch (found, expected) {
        case let (found?, expected?):
            return found.unicodeScalars.elementsEqual(expected.unicodeScalars)

        default:
            return found == nil && expected == nil
        }
    }

    /// `location` as `path:line:column`, the path as a Swift literal.
    static func shown(_ location: PeripheryFields.Location?) -> String {
        location.map { "\($0.path.debugDescription):\($0.line):\($0.column)" } ?? "no location"
    }

    /// The classes `draft` falls in, for P9.2's tally and the generator's
    /// meta-test.
    static func entryLabels(of draft: PeripheryEntryDraft) -> [String] {
        guard draft.notObject == nil else {
            return [notAnObject]
        }
        let keyFaults = draft.keyFaults
        let hintsFault = draft.hintCount.map { $0 != 1 } ?? false
        let locationFault = draft.location.map { $0.expected == nil } ?? false
        let mixed = keyFaults.contains { key, field in
            guard PeripheryEntryDraft.listKeys.contains(key), case .wrong(.array) = field else {
                return false
            }
            return true
        }
        let mistyped = keyFaults.contains { key, field in
            guard PeripheryEntryDraft.listKeys.contains(key) == false, case .wrong = field else {
                return false
            }
            return true
        }
        var isPadded = false
        if case .padded = draft.location?.flaw {
            isPadded = true
        }
        let isRead = draft.faults.isEmpty
        var isZero = false
        if case .number(.zero, _) = draft.location?.flaw {
            isZero = true
        }
        var isSigned = false
        if case .number(.signed, _) = draft.location?.flaw {
            isSigned = true
        }
        return [
            (isRead, reads),
            (keyFaults.contains { $0.field == .missing }, missingKey),
            (mistyped, mistypedString),
            (mixed, mixedList),
            (hintsFault, wrongHintCount),
            (locationFault, badLocation),
            (keyFaults.count > 1, twoKeyFaults),
            (keyFaults.isEmpty == false && hintsFault, keyBesideHints),
            (keyFaults.isEmpty == false && locationFault, keyBesideLocation),
            (keyFaults.isEmpty && hintsFault && locationFault, hintsBesideLocation),
            (isRead && isPadded, padded),
            (isZero && draft.faults.count == 1, zeroAlone),
            (isSigned && draft.faults.count == 1, signedAlone)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `read`, what reading an entry gave, is what `expected`
    /// says: its fields, or a `FormatFailure` with exactly the reason
    /// expected, never another error. Records an issue for each law that
    /// fails.
    static func checkFields(_ expected: PeripheryEntryDraft.Expected, read: Read) -> Bool {
        let subject = "reading the entry"
        switch (expected, read) {
        case let (.accepted(strings, lists, location), .success(fields)):
            return holds(
                [
                    (fields.strings == strings, "reads strings \(fields.strings), expected \(strings)"),
                    (fields.lists == lists, "reads lists \(fields.lists), expected \(lists)"),
                    (
                        same(fields.location, location),
                        "reads location \(shown(fields.location)), expected \(shown(location))"
                    )
                ],
                subject: subject
            )

        case (.accepted, .failure(let error)):
            return holds([(false, "fails: \(error), where it should read")], subject: subject)

        case (.refused(let reason), .success):
            return holds([(false, "reads, expected: " + reason)], subject: subject)

        case let (.refused(reason), .failure(error)):
            guard let failure = error as? PeripheryOutput.FormatFailure else {
                return holds([(false, "throws \(error), not a FormatFailure")], subject: subject)
            }
            return holds(
                [(failure.description == reason, "fails: \(failure.description), expected: " + reason)],
                subject: subject
            )
        }
    }

    /// A draft of an object entry, the 7th of the roots run, whose keys
    /// hold `fields`, sound ones where `fields` names none.
    static func draft(_ fields: [String: PeripheryEntryDraft.Field]) -> PeripheryEntryDraft {
        let location = LocationDraft(path: "/NoSuchPeripheryPackage/a.swift", line: 3, column: 6, flaw: .sound)
        let sound: [String: PeripheryEntryDraft.Field] = [
            "accessibility": .string("internal"), "attributes": .list([]), "hints": .list(["unused"]),
            "ids": .list(["s:9IndexCore1fyyF"]), "kind": .string("function.free"), "location": .location(location),
            "modifiers": .list([]), "modules": .list(["IndexCore"]), "name": .string("f()")
        ]
        return PeripheryEntryDraft(
            notObject: nil,
            fields: PeripheryEntryDraft.keys.map { fields[$0] ?? sound[$0] ?? .missing },
            extras: [],
            ordinal: 7,
            run: .roots
        )
    }

    // MARK: P9.2

    /// Invariant: reading an entry gives its fields exactly when it is an
    /// object, none of the nine keys is missing or of another type, it
    /// holds one hint and its location reads; otherwise it fails naming
    /// the entry's ordinal and run and the first fault in the reader's
    /// order: the keys in order, then the hints, then the location.
    /// Why it holds: `PeripheryOutput`'s header (each fault is a format
    /// failure, the first named), the doc comment of
    /// `fields(of:ordinal:run:)` (the order), design §5.3 (the nine keys
    /// and their types), and `PeripheryFields.Location`'s doc comment.
    /// Why it might not: extra keys are ignored, near misses of the nine
    /// (`Kind`, `location `) included, since keys are matched exactly; a
    /// number with leading zeros still reads, as its digits spell it (the
    /// doc comment's "positive number of decimal digits"); duplicate keys
    /// aren't drawn (which one `JSONSerialization` keeps is its choice);
    /// no text starts with U+FEFF (assumed: `JSONSerialization` drops it,
    /// B29 awaiting U17, pinned in `PeripheryOutputTests+Scalars`).
    /// Oracle: the generating model (`PeripheryEntryDraft.expected`);
    /// planted defects: the last faulty key named, the hints counted
    /// before the keys, the location read before the hints, a list
    /// holding a number read, line 0 read, a signed line read and another
    /// error thrown, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "an entry reads exactly when no part is faulty, else its first fault in the reader's order is named",
        .timeLimit(PBTBudget.timeLimit)
    )
    func entriesNameTheirFirstFault() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.entryRuns), input: PeripheryJSONGen.entry) { draft in
            PBTTrace.note(draft)
            Self.entryLabels(of: draft).forEach(tally.fire)
            guard let element = PeripheryEntryDraft.element(of: draft.data) else {
                PBTTrace.firstFailure(draft, latch: latch)
                return
            }
            let read = Read { try PeripheryOutput.fields(of: element, ordinal: draft.ordinal, run: draft.run) }
            if Self.checkFields(draft.expected, read: read) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.entryAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }
}
