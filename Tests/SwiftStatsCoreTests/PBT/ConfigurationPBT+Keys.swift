//
//  ConfigurationPBT+Keys.swift
//  SwiftStatsCoreTests
//
//  P11.3, its shared check, its examples (unknown keys at each level with
//  the reader's exact words, keys Yams refuses as repeated, a key YAML
//  reads as two types) and the meta-tests feeding planted defects'
//  readings to the check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P11.3's property, check, examples and planted defects.
extension ConfigurationPBT {
    /// P11.3's base runs, over the engine's 100: drawing and reading one
    /// text costs about a third of a millisecond. The rarest antecedent, a
    /// key YAML reads as two types repeated at the top, the one input on
    /// which the reader's own repeat check shows, came in 3,454 of 200,000
    /// faults drawn from 200 seeds (1.73%; at least 1.63% at 99.9%
    /// confidence; the meta-test's one seed gives 19 of 1,000, above the
    /// rate). Design D14: `(1 - 0.0163)^900`, about 4 * 10^-7, is the most
    /// a run misses it; 800 runs would miss it about 10^-6 of the time.
    /// Unknown keys in swiftmutator's options came in 3.8%.
    static let keyRuns = 900
    /// What P11.3's tally counts for unknown keys at the top level.
    static let unknownAtTop = "an unknown key at the top"
    /// What it counts for unknown keys under `history` or `signals`.
    static let unknownInSection = "an unknown key under history or signals"
    /// What it counts for unknown keys under `history.coupling` or a signal.
    static let unknownDeeper = "an unknown key under history.coupling or a signal"
    /// What it counts for unknown keys in a collector's entry.
    static let unknownInCollector = "an unknown key in a collector's entry"
    /// What it counts for unknown keys in swiftmutator's options.
    static let unknownInOptions = "an unknown key in swiftmutator's options"
    /// What it counts for two unknown keys in one mapping.
    static let twoUnknown = "two unknown keys in one mapping"
    /// What it counts for a key repeated as written.
    static let repeatedAlike = "a key repeated as written"
    /// What it counts for a key repeated in other quotes, read alike.
    static let repeatedRequoted = "a key repeated in other quotes, read alike"
    /// What it counts for a key YAML reads as two types, at the top.
    static let twoTypesAtTop = "a key read as two types at the top"
    /// What it counts for a key YAML reads as two types, nested.
    static let twoTypesNested = "a key read as two types, nested"
    /// What it counts for a collector named twice.
    static let collectorTwice = "a collector named twice"
    /// The antecedents P11.3 must reach at least once each.
    static let keyAntecedents = [
        unknownAtTop, unknownInSection, unknownDeeper, unknownInCollector, unknownInOptions, twoUnknown, repeatedAlike,
        repeatedRequoted, twoTypesAtTop, twoTypesNested, collectorTwice
    ]

    /// The classes `fault` falls in, for P11.3's tally and the generator's
    /// meta-test.
    static func keyLabels(of fault: KeyFault) -> [String] {
        switch fault.kind {
        case let .duplicate(key, first, second):
            let twoTypes = KeyFault.typedKeys.contains(key) && (first == .plain) != (second == .plain)
            let kind = twoTypes ? (fault.level.isEmpty ? twoTypesAtTop : twoTypesNested)
                : (first == second ? repeatedAlike : repeatedRequoted)
            return fault.level == ConfigGen.namesLevel ? [kind, collectorTwice] : [kind]

        case .unknown(let keys):
            let place: String
            switch (fault.level.first ?? "", fault.level.count) {
            case (_, 0):
                place = unknownAtTop

            case ("collectors", ConfigGen.workersPath.count - 1):
                place = unknownInOptions

            case ("collectors", _):
                place = unknownInCollector

            case (_, 1):
                place = unknownInSection

            default:
                place = unknownDeeper
            }
            return Set(keys.compactMap(\.keyText)).count > 1 ? [place, twoUnknown] : [place]
        }
    }

    /// Whether `read`, what reading a text holding a key fault gave, is
    /// the refusal `expected` says: Yams' naming the repeated key, or
    /// exactly the reader's reason. Records an issue for each law that
    /// fails.
    static func checkKeys(_ expected: KeyFault.Expected, read: Read) -> Bool {
        let subject = "reading the faulty keys"
        guard case .failure(let error) = read else {
            return holds([(false, "accepts them")], subject: subject)
        }
        guard let reason = reason(of: error) else {
            return holds([(false, "throws \(error), not a configuration error naming \(file)")], subject: subject)
        }
        switch expected {
        case .duplicateInYAML(let key):
            let phrase = "found the following duplicated key(s): '\(key)'."
            return holds(
                [
                    (
                        reason.hasPrefix("not valid YAML: ") && reason.contains(phrase),
                        "refuses them: \(reason), expected Yams naming \(key.debugDescription) as repeated"
                    )
                ],
                subject: subject
            )

        case .refused(let expectedReason):
            return holds(
                [(reason == expectedReason, "refuses them: \(reason), expected: \(expectedReason)")],
                subject: subject
            )
        }
    }

    // MARK: P11.3

    /// Invariant: an unknown key, or a key given twice, at any level of a
    /// configuration is refused, naming it.
    /// Why it holds: PRD §10.1 ("other unknown keys, at any level, ...
    /// are an error"; unknown keys under the signals "are errors naming
    /// the key"); design §4.1.6 (P11.3); the reader's doc comments and
    /// messages (unknown keys named sorted, by their dotted path in a
    /// collector's entry; a top-level key repeated "given more than
    /// once"); Yams refuses a repeat of the same YAML type as it composes.
    /// Why it might not: an unknown collector name is accepted with a
    /// warning (PRD §10.1), so it is never drawn as unknown; keys are
    /// plain or quoted scalars only (assumed: a tagged key or one that
    /// isn't text is design B31 and B32, awaiting U21, pinned in
    /// `ConfigurationKeyTests`); a key YAML reads as two types is unknown
    /// at every nested level, so it is named as unknown there.
    /// Oracle: the generating model (`KeyFault.expected`); planted
    /// defects: the keys accepted, unknown keys named unsorted, a
    /// collector's keys named without their path, and a repeat not named,
    /// each detected.
    /// Tier: Strict (stop-ship).
    @Test("an unknown key, or a key given twice, at any level is refused, naming it", .timeLimit(PBTBudget.timeLimit))
    func faultyKeysRefused() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.keyRuns), input: ConfigGen.keyFaultCase) { draft in
            PBTTrace.note(draft)
            Self.keyLabels(of: draft.fault).forEach(tally.fire)
            let read = Read { try SwiftStatsConfiguration.parse(draft.text, path: Self.file) }
            if Self.checkKeys(draft.fault.expected, read: read) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.keyAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("unknown keys at each level are refused in the reader's words, sorted, a collector's by their path")
    func unknownKeysNamed() {
        let texts: [(String, String)] = [
            ("stores: x\nexclude: [a]\n", "unknown key(s): exclude, stores"),
            ("history:\n  windows: 3d\n", "unknown key(s) under `history`: windows"),
            ("history: {coupling: {min_support: 3, Window: 1}}\n", "unknown key(s) under `history.coupling`: Window"),
            ("signals:\n  hotspot:\n    thresholds: 5\n", "unknown key(s) under `signals.hotspot`: thresholds"),
            (
                "collectors:\n  jazzy:\n    enable: true\n    \"a b\": 1\n",
                "unknown key(s): collectors.jazzy.a b, collectors.jazzy.enable"
            ),
            (
                "collectors: {swiftmutator: {options: {Workers: 2}}}\n",
                "unknown key(s): collectors.swiftmutator.options.Workers"
            )
        ]

        for (text, reason) in texts {
            let read = Read { try SwiftStatsConfiguration.parse(text, path: Self.file) }

            #expect(Self.checkKeys(.refused(reason), read: read), "\(text)")
        }
    }

    @Test("""
        a key repeated with one YAML type is refused by Yams naming it, at the top, nested and as a collector; one \
        read as two types is given more than once at the top and unknown nested
        """)
    func repeatedKeysNamed() {
        let texts: [(String, KeyFault.Expected)] = [
            ("store: a\n'store': b\n", .duplicateInYAML("store")),
            ("history:\n  window: 3d\n  \"window\": 4d\n", .duplicateInYAML("window")),
            ("collectors: {swiftlint: ~, swiftlint: {}}\n", .duplicateInYAML("swiftlint")),
            ("1: a\n\"1\": b\n", .refused("key(s) given more than once: 1")),
            ("signals:\n  true: 1\n  'true': 2\n", .refused("unknown key(s) under `signals`: true"))
        ]

        for (text, expected) in texts {
            let read = Read { try SwiftStatsConfiguration.parse(text, path: Self.file) }

            #expect(Self.checkKeys(expected, read: read), "\(text)")
        }
    }

    @Test("a planted defect's reading of faulty keys fails P11.3's law")
    func keyDefectsDetected() throws {
        let sound = try SwiftStatsConfiguration.parse("", path: Self.file)
        let unsorted = ScanError.configurationInvalid(Self.file, "unknown key(s): stores, exclude")
        let pathless = ScanError.configurationInvalid(Self.file, "unknown key(s): enable")
        let unnamed = ScanError.configurationInvalid(Self.file, "a key under `history` is given more than once")

        PlantedDefect.expectDetected("the keys accepted", sourceLocation: #_sourceLocation) {
            Self.checkKeys(.refused("unknown key(s): stores"), read: .success(sound))
        }
        PlantedDefect.expectDetected("unknown keys named unsorted", sourceLocation: #_sourceLocation) {
            Self.checkKeys(.refused("unknown key(s): exclude, stores"), read: .failure(unsorted))
        }
        PlantedDefect.expectDetected("a collector's key named without its path", sourceLocation: #_sourceLocation) {
            Self.checkKeys(.refused("unknown key(s): collectors.jazzy.enable"), read: .failure(pathless))
        }
        PlantedDefect.expectDetected("a repeat not named", sourceLocation: #_sourceLocation) {
            Self.checkKeys(.duplicateInYAML("window"), read: .failure(unnamed))
        }
    }
}
