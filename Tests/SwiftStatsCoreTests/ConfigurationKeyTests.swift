import Foundation
@testable import SwiftStatsCore
import Testing

/// Keys and numbers the configuration reader reads unlike the rest of the
/// file, found by step 14's probes for P11.1 to P11.3 and pinned as known
/// issues until the user decides (design D17). B31: a key that isn't text
/// (`[a, b]: c`, `? {a: b}`) is dropped where the reader lists keys, so it
/// is accepted at the top level, under `history`, `signals`, a signal and
/// a collector's entry, where PRD §10.1 makes an unknown key at any level
/// an error. B32: a tagged key (`!t excluded`) counts as its text when the
/// reader checks keys but isn't found when it reads values, so its value
/// is ignored, and a repeat by text is refused unnamed under `history` and
/// `signals` and not refused under a collector or swiftmutator's
/// `options`. Both await U21; the expectations are the recommended
/// reading, keys read by their text everywhere. B33: swiftmutator's
/// `workers` and `timeout` take only YAML numbers, through Yams, so a
/// quoted number is refused there, where every other numeric key reads
/// its text, quoted or not; awaiting U22, the expectation is the
/// recommended reading, a quoted number read as the plain one.
@Suite("Configuration keys and quoted numbers")
struct ConfigurationKeyTests {
    /// What reading `text` gives.
    static func parsed(_ text: String) -> Result<SwiftStatsConfiguration, any Error> {
        Result { try SwiftStatsConfiguration.parse(text, path: "c.yml") }
    }

    @Test(
        "a key that isn't text is refused wherever it is (B31, awaiting U21)",
        arguments: [
            "[a, b]: c\n", "? {a: b}\n: 1\nexcluded: [x]\n", "history:\n  ? [a]\n  : 1\n", "signals:\n  ? [a]\n  : 1\n",
            "signals:\n  hotspot:\n    ? [a]\n    : 1\n", "collectors:\n  swiftlint:\n    ? [a]\n    : 1\n"
        ]
    )
    func nonTextKeys(text: String) {
        withKnownIssue("B31: awaiting U21") {
            #expect(throws: ScanError.self) { try Self.parsed(text).get() }
        }
    }

    @Test("a tagged key is read by its text: its value taken, a repeat by text refused naming it (B32, awaiting U21)")
    func taggedKeys() throws {
        let tagged = try Self.parsed("!t excluded: [b]\n").get()
        let collectorRepeat = Self.parsed("collectors:\n  swiftlint:\n    enabled: true\n    !t enabled: false\n")
        let historyRepeat = Self.parsed("history:\n  window: 3d\n  !t window: 4d\n")

        withKnownIssue("B32: awaiting U21") {
            #expect(tagged.excluded == ["b"])
            #expect(throws: ScanError.self) { try collectorRepeat.get() }
            #expect("\(historyRepeat)".contains("window"))
        }
        #expect(throws: ScanError.self) { try historyRepeat.get() }
        #expect(throws: ScanError.self) { try Self.parsed("excluded: [a]\n!t excluded: [b]\n").get() }
    }

    @Test("a quoted number reads as the plain one for workers and timeout, as for other numbers (B33, awaiting U22)")
    func quotedNumbers() throws {
        let options = Self.parsed("collectors:\n  swiftmutator:\n    options: {workers: \"4\", timeout: '30'}\n")
        let others = try Self.parsed("history: {bulk_files: \"30\"}\nsignals: {hotspot: {threshold: '5'}}\n").get()

        withKnownIssue("B33: awaiting U22") {
            let mutator = try options.get().collectors["swiftmutator"]
            #expect(mutator?.workers == 4)
            #expect(mutator?.timeout == 30)
        }
        #expect(others.history.bulkFiles == 30)
        #expect(others.signals.percent(for: "hotspot") == 5)
    }
}
