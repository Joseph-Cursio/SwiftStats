import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of reading `.swiftstats.yml` (PRD §10.1, design §4.1.6):
/// any YAML text reads as a configuration or a configuration error naming
/// the file, never traps, and a valid configuration reads (P11.1); each
/// bound PRD §10.1 states accepts its edge, read as written, and refuses
/// one step outside it, naming the key, whatever the style (P11.2); and an
/// unknown key, or a key given twice, at any level is refused, naming it
/// (P11.3). Each is asserted on `SwiftStatsConfiguration.parse(_:path:)`,
/// the reader `load` calls once the file is read as UTF-8. The fixed
/// examples are in `ConfigurationTests` and the per-collector suites;
/// each property here has its own, calling its shared check, and
/// meta-tests that feed a planted defect's reading to that check.
@Suite("Configuration: properties", .tags(.pbt))
struct ConfigurationPBT {
    /// What reading a text gives.
    typealias Read = Result<SwiftStatsConfiguration, any Error>

    /// The path every text is read as, which its errors must name.
    static let file = "c.yml"

    /// P11.1's base runs, over the engine's 100: drawing and reading one
    /// text costs about a third of a millisecond. The rarest antecedent, a
    /// configuration written in flow style from the top, comes in 38 of
    /// the meta-test's 1,000 texts (design D14: `(1 - 0.038)^400`, about
    /// 2 * 10^-7, is the most a run misses it); an anchored section and
    /// its alias comes in 51, and a base-60 `workers` past `Int`, the input
    /// on which Yams' reading trapped (B30), in 52.
    static let anyRuns = 400
    /// What P11.1's tally counts for a valid configuration.
    static let validText = "a valid configuration"
    /// What it counts for a value spelled oddly.
    static let oddSpelling = "a value spelled oddly"
    /// What it counts for a base-60 `workers` past `Int`.
    static let baseSixtyWorkers = "a base-60 workers past Int"
    /// What it counts for a value of another type.
    static let otherType = "a value of another type"
    /// What it counts for unknown or repeated keys.
    static let faultyKey = "an unknown or repeated key"
    /// What it counts for a key that isn't plain text.
    static let exoticKey = "a key that isn't plain text"
    /// What it counts for an anchored section and its alias.
    static let aliasedSection = "a section and its alias"
    /// What it counts for text that isn't a configuration.
    static let soupText = "text that isn't a configuration"
    /// What it counts for a configuration written in flow style from the top.
    static let flowFromTop = "flow style from the top"
    /// What it counts for lines ending in `\r\n`.
    static let crlfLines = "lines ending in CRLF"
    /// What it counts for something before the first key.
    static let prefixed = "something before the first key"
    /// The antecedents P11.1 must reach at least once each.
    static let anyAntecedents = [
        validText, oddSpelling, baseSixtyWorkers, otherType, faultyKey, exoticKey, aliasedSection, soupText,
        flowFromTop, crlfLines, prefixed
    ]

    /// Records an issue naming `subject`, in ASCII, for each law in `laws`
    /// that fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record(Comment(rawValue: PBTTrace.ascii("\(subject) fails: it \(law.law)")))
        }
        return laws.allSatisfy(\.holds)
    }

    /// The reason of `error` when it is a configuration error naming
    /// `file`; nil for any other error.
    static func reason(of error: any Error) -> String? {
        guard case let .configurationInvalid(path, reason)? = error as? ScanError, path == file else {
            return nil
        }
        return reason
    }

    /// The classes `draft` falls in, for P11.1's tally and the generator's
    /// meta-test.
    static func anyLabels(of draft: ConfigCase) -> [String] {
        var labels: [String] = []
        switch draft.flaw {
        case .aliased:
            labels.append(aliasedSection)

        case .exoticKey:
            labels.append(exoticKey)

        case .keyFault:
            labels.append(faultyKey)

        case let .spelling(path, text):
            labels.append(oddSpelling)
            if path == ConfigGen.workersPath, ConfigGen.baseSixtyTraps.contains(text) {
                labels.append(baseSixtyWorkers)
            }

        case .wrongType:
            labels.append(otherType)

        case nil:
            labels.append(draft.soup == nil ? validText : soupText)
        }
        guard draft.soup == nil else {
            return labels
        }
        return labels + [
            (draft.layout.flowDepth == 0, flowFromTop),
            (draft.layout.endsInCRLF, crlfLines),
            (draft.layout.prefix.isEmpty == false, prefixed)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `read`, what reading a text gave, is a configuration, or a
    /// configuration error naming `file` for a text that isn't `isValid`.
    /// Records an issue for each law that fails.
    static func checkTotal(isValid: Bool, read: Read) -> Bool {
        let subject = "reading the text"
        guard case .failure(let error) = read else {
            return true
        }
        guard let reason = reason(of: error) else {
            return holds([(false, "throws \(error), not a configuration error naming \(file)")], subject: subject)
        }
        return holds([(isValid == false, "refuses a valid configuration: \(reason)")], subject: subject)
    }

    // MARK: P11.1

    /// Invariant: reading any YAML text returns a configuration or throws
    /// a configuration error naming the file, never traps and never throws
    /// another error, and a valid configuration is read.
    /// Why it holds: design §4.1.6 (P11.1); `SwiftStatsConfiguration`'s
    /// doc comments (`parse` wraps every YAML error as "not valid YAML",
    /// and every other refusal is `ScanError.configurationInvalid` naming
    /// the path); PRD §10.1 for what a valid configuration holds.
    /// Why it might not: a flawed text may be accepted (an anchored
    /// section aliased under another key the other key takes) or refused,
    /// whichever the reader's rules say; only valid texts must read.
    /// Nesting is at most four levels and texts at most 40 fragments
    /// (assumed: a configuration is small; 3,000 nested sequences read
    /// without trouble, step 14's probe).
    /// Oracle: postconditions, and the generating model for valid texts;
    /// planted defects: Yams' error thrown unwrapped, an error naming
    /// another file, a valid configuration refused (a known key or a valid
    /// spelling forgotten), and B30's trap undone, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "reading any YAML text returns a configuration or a configuration error naming the file, and a valid one reads",
        .timeLimit(PBTBudget.timeLimit)
    )
    func anyTextReads() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.anyRuns), input: ConfigGen.anyCase) { draft in
            PBTTrace.note(draft)
            Self.anyLabels(of: draft).forEach(tally.fire)
            let read = Read { try SwiftStatsConfiguration.parse(draft.text, path: Self.file) }
            if Self.checkTotal(isValid: draft.isValid, read: read) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.anyAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }
}
