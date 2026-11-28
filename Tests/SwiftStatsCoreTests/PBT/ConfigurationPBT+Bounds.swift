//
//  ConfigurationPBT+Bounds.swift
//  SwiftStatsCoreTests
//
//  P11.2, the walk over every bound PRD §10.1 states, its shared check,
//  its examples (hand-written texts at timeout's, the longest duration's
//  and uneven clone mutation's edges, in block and flow style, plain and
//  quoted) and the meta-tests feeding planted defects' readings to the
//  check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P11.2's walk, check, examples and planted defects.
extension ConfigurationPBT {
    /// P11.2's base runs per edge, under the engine's 100: each run draws
    /// the edge, the value one step outside it or the value far outside
    /// it, a third of the time each, so a side never drawn in 36 runs has
    /// chance (2/3)^36, about 5 * 10^-7 (design D14), and 41 edges read
    /// 1,476 texts in all, under a second. The styles (block or flow, plain
    /// or quoted) are sampled, not required: the law doesn't depend on
    /// them (in the meta-test's 1,000 cases of one edge, 675 are quoted
    /// and 162 in flow style).
    static let boundRuns = 36
    /// What P11.2's tally counts for the edge.
    static let atEdge = "the edge"
    /// What it counts for the value one step outside.
    static let outsideEdge = "one step outside"
    /// What it counts for the value far outside.
    static let farOutside = "far outside"
    /// What it counts for a quoted value.
    static let quotedValue = "a quoted value"
    /// What it counts for a value in flow style.
    static let flowValue = "a value in flow style"

    /// The classes `draft` falls in, for P11.2's tally and the generator's
    /// meta-test.
    static func boundLabels(of draft: BoundCase) -> [String] {
        [
            (draft.isOutside == false, atEdge),
            (draft.isOutside && draft.isFar == false, outsideEdge),
            (draft.isFar, farOutside),
            (draft.quote != .plain, quotedValue),
            (draft.layout.flowDepth < draft.bound.path.count, flowValue)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether `read`, what reading a text holding `bound`'s edge (or a
    /// value outside it, one step or far, when `isOutside`) gave, is the
    /// edge read as written, or exactly the bound's refusal. Records an
    /// issue for each law that fails.
    static func checkBound(_ bound: ConfigBound, isOutside: Bool, read: Read) -> Bool {
        let subject = "reading \(bound.name)"
        switch (isOutside, read) {
        case (false, .success(let configuration)):
            let found = bound.read(configuration)
            let shown = found.map { "\($0)" } ?? "nothing"
            return holds(
                [(found != nil && found == bound.value, "reads \(shown) for the edge \(bound.edge)")],
                subject: subject
            )

        case (false, .failure(let error)):
            return holds([(false, "refuses the edge \(bound.edge): \(error)")], subject: subject)

        case (true, .success):
            return holds([(false, "accepts a value outside the edge \(bound.edge)")], subject: subject)

        case (true, .failure(let error)):
            let found = reason(of: error)
            return holds(
                [(found == bound.reason, "refuses a value outside with \(error), expected: \(bound.reason)")],
                subject: subject
            )
        }
    }

    /// The edge of the walk named `name`.
    static func bound(named name: String) throws -> ConfigBound {
        try #require(ConfigBounds.all.first { $0.name == name })
    }

    // MARK: P11.2

    /// Invariant: each bound PRD §10.1 states accepts the value at its
    /// edge, read as written, and refuses the value one step outside it,
    /// and one far outside it, with the reason naming the key, in block or
    /// flow style, plain or quoted, among any valid keys.
    /// Why it holds: PRD §10.1 (durations at most 106,751,991,167,300
    /// days; thresholds a percent; the M6 and M7 limits' table: percents
    /// 0 to 100, counts 1 to 1,000,000, a ratio above 0, `high` above
    /// `low`; `workers` at least 1, `timeout` above 0 and at most 86,400);
    /// the reader's doc comments for the floors (a duration at least a
    /// day, `bulk_files` at least 1, `min_support` at least 2) and for the
    /// thresholds' (0, 100].
    /// Why it might not: one step is a day, one, or the next `Double`, as
    /// the key is read, and far is one value past it (`ConfigBounds`);
    /// `workers` and `timeout` are written plain only
    /// (assumed: a quoted number there is refused, design B33, awaiting
    /// U22, pinned in `ConfigurationKeyTests`); the walk's cases are the
    /// edges, the styles are sampled.
    /// Oracle: the bounds' table written from PRD §10.1
    /// (`ConfigBounds`); planted defects: an edge refused (`<` for `<=`),
    /// a value outside accepted, an edge read as another value, and the
    /// wrong key named, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "each bound PRD 10.1 states accepts its edge as written, refuses one step outside and beyond, naming the key",
        .timeLimit(PBTBudget.timeLimit),
        arguments: ConfigBounds.all
    )
    func boundsHoldAtTheirEdges(bound: ConfigBound) async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.boundRuns), input: ConfigGen.boundCase(bound)) { draft in
            PBTTrace.note(draft)
            Self.boundLabels(of: draft).forEach(tally.fire)
            let read = Read { try SwiftStatsConfiguration.parse(draft.text, path: Self.file) }
            if Self.checkBound(draft.bound, isOutside: draft.isOutside, read: read) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(
            [Self.atEdge, Self.outsideEdge, Self.farOutside],
            unlessFailed: latch,
            sourceLocation: #_sourceLocation
        )
    }

    @Test("swiftmutator's timeout reads at a day and the least positive number, in block and flow style")
    func timeoutEdges() throws {
        let day = try Self.bound(named: "timeout at most a day")
        let least = try Self.bound(named: "timeout above 0")
        let cases: [(bound: ConfigBound, texts: [(isOutside: Bool, text: String)])] = [
            (
                day,
                [
                    (false, "collectors:\n  swiftmutator:\n    options:\n      timeout: 86400\n"),
                    (true, "collectors: {swiftmutator: {options: {timeout: 86400.00000000001}}}\n")
                ]
            ),
            (
                least,
                [
                    (false, "collectors:\n  swiftmutator:\n    options: {workers: 2, timeout: 5e-324}\n"),
                    (true, "collectors:\n  swiftmutator: {options: {timeout: 0}}\n")
                ]
            )
        ]

        for (bound, texts) in cases {
            for (isOutside, text) in texts {
                let read = Read { try SwiftStatsConfiguration.parse(text, path: Self.file) }

                #expect(Self.checkBound(bound, isOutside: isOutside, read: read), "\(text)")
            }
        }
    }

    @Test("the longest duration reads, plain or quoted, and a day more is refused naming history.window")
    func longestDuration() throws {
        let longest = try Self.bound(named: "history.window at most 106751991167300 days")
        let texts: [(Bool, String)] = [
            (false, "history:\n  window: 106751991167300d\n"),
            (false, "history: {window: '106751991167300d'}\n"),
            (true, "history:\n  window: \"106751991167301d\"\n")
        ]

        for (isOutside, text) in texts {
            let read = Read { try SwiftStatsConfiguration.parse(text, path: Self.file) }

            #expect(Self.checkBound(longest, isOutside: isOutside, read: read), "\(text)")
        }
        #expect(longest.value == 106_751_991_167_300)
    }

    @Test("uneven clone mutation's high reads just above its low, set or default, and is refused at it")
    func cloneEdges() throws {
        let setLow = try Self.bound(named: "uneven-clone-mutation.high above a low of 50")
        let defaultLow = try Self.bound(named: "uneven-clone-mutation.high above the default low, 20")
        let cases: [(bound: ConfigBound, texts: [(isOutside: Bool, text: String)])] = [
            (
                setLow,
                [
                    (false, "signals:\n  uneven-clone-mutation:\n    low: 50\n    high: 50.00000000000001\n"),
                    (true, "signals: {uneven-clone-mutation: {high: \"50\", low: '50'}}\n")
                ]
            ),
            (
                defaultLow,
                [
                    (false, "signals:\n  uneven-clone-mutation:\n    high: 20.000000000000004\n"),
                    (true, "signals:\n  uneven-clone-mutation: {high: 20, mutants: 2}\n")
                ]
            )
        ]

        for (bound, texts) in cases {
            for (isOutside, text) in texts {
                let read = Read { try SwiftStatsConfiguration.parse(text, path: Self.file) }

                #expect(Self.checkBound(bound, isOutside: isOutside, read: read), "\(text)")
            }
        }
    }

    @Test("a planted defect's reading of a bound fails P11.2's law")
    func boundDefectsDetected() throws {
        let threshold = try Self.bound(named: "hotspot threshold at most 100")
        let least = try Self.bound(named: "timeout above 0")
        let edgeText = "signals:\n  hotspot:\n    threshold: 100\n"
        let sound = try SwiftStatsConfiguration.parse(edgeText, path: Self.file)
        let other = try SwiftStatsConfiguration.parse("signals:\n  hotspot:\n    threshold: 99\n", path: Self.file)
        let refusal = ScanError.configurationInvalid(Self.file, threshold.reason)

        #expect(Self.checkBound(threshold, isOutside: false, read: .success(sound)))
        PlantedDefect.expectDetected("the edge refused, a < for a <=", sourceLocation: #_sourceLocation) {
            Self.checkBound(threshold, isOutside: false, read: .failure(refusal))
        }
        PlantedDefect.expectDetected("the value outside accepted", sourceLocation: #_sourceLocation) {
            Self.checkBound(threshold, isOutside: true, read: .success(sound))
        }
        PlantedDefect.expectDetected("the edge read as another value", sourceLocation: #_sourceLocation) {
            Self.checkBound(threshold, isOutside: false, read: .success(other))
        }
        PlantedDefect.expectDetected("the wrong key named", sourceLocation: #_sourceLocation) {
            Self.checkBound(least, isOutside: true, read: .failure(refusal))
        }
    }
}
