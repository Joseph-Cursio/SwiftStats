import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the integer-edge generators draw (design D14): the edges are 0, 1
/// and `Int.max - 3` through `Int.max`, 1 three times as likely as each
/// other; and from a fixed seed, a thousand drafts of each path reach each
/// antecedent of its P15.1 property an exact number of times: a record
/// mapped onto the package, its output failed, and a record that comes
/// back held by nothing; a field at `Int.max` and one at 0; and each
/// path's own (a copy below 1 or inverted, a column after a byte order
/// mark too large to shift; a `mutant` line read, at 1:1, with the
/// largest occurrence, a complete kill list; SwiftProjectLint's schema
/// read, a violation and an issue on a record, a place unscanned). The
/// counts hold under this engine's generator code and this standard
/// library; a change to either, or to a list in `IntegerEdgeGen`, redraws
/// them.
@Suite("Integer edge generators")
struct IntegerEdgeGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: no generator rejects a value, so one
    /// is enough, and a filter added later fails here instead of hanging.
    static let attempts = 1
    /// The fixed seed the meta-tests draw from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    /// How often each label of `labels` comes up over `draws` draws from
    /// `generator`, starting from `seeded`.
    static func counts<Value>(
        _ generator: Generator<Value, some Sequence>,
        labels: (Value) -> [String]
    ) throws -> [String: Int] {
        var random = seeded
        var counts: [String: Int] = [:]
        for _ in 0..<draws {
            for label in labels(try generator.run(using: &random, limit: attempts)) {
                counts[label, default: 0] += 1
            }
        }
        return counts
    }

    @Test("the edges are 0, 1 and Int.max - 3 through Int.max, and 1 is drawn three times as often as each other")
    func edgesAreTheDesigns() throws {
        let counts = try Self.counts(IntegerEdgeGen.edge) { [String($0)] }

        #expect(IntegerEdgeGen.edges == [
            0, 1, 9_223_372_036_854_775_804, 9_223_372_036_854_775_805, 9_223_372_036_854_775_806, .max
        ])
        #expect(Set(counts.keys) == Set(IntegerEdgeGen.edges.map(String.init)))
        #expect(counts == [
            "0": 145, "1": 332, "9223372036854775804": 133, "9223372036854775805": 141, "9223372036854775806": 110,
            "9223372036854775807": 139
        ])
    }

    @Test("a thousand clone reports reach each antecedent of the clone path an exact number of times")
    func cloneClasses() throws {
        let counts = try Self.counts(IntegerEdgeGen.clones, labels: IntegerEdgesPBT.cloneLabels(of:))

        #expect(counts == [
            "a column after a byte order mark too large to shift": 55,
            "a copy ending before it starts": 222,
            "a copy with a position below 1": 575,
            "a field at 0": 837,
            "a field at Int.max": 856,
            "failed": 797,
            "mapped onto a record": 52,
            "unknown": 199
        ])
    }

    @Test("a thousand results files reach each antecedent of the results path an exact number of times")
    func resultsClasses() throws {
        let counts = try Self.counts(IntegerEdgeGen.results, labels: IntegerEdgesPBT.resultsLabels(of:))

        #expect(counts == [
            "a complete kill list": 79,
            "a field at 0": 722,
            "a field at Int.max": 759,
            "a mutant line read": 225,
            "a mutant line read at 1:1": 29,
            "an occurrence of Int.max": 250,
            "failed": 775,
            "mapped onto a record": 162,
            "the not-covered key tested": 2,
            "unknown": 890
        ])
    }

    @Test("a thousand pairs of lint reports reach each antecedent of the findings path an exact number of times")
    func findingClasses() throws {
        let counts = try Self.counts(IntegerEdgeGen.lints, labels: IntegerEdgesPBT.findingLabels(of:))

        #expect(counts == [
            "SwiftProjectLint's schema read": 390,
            "a field at 0": 594,
            "a field at Int.max": 631,
            "a place unscanned": 812,
            "a violation on a record": 334,
            "an issue on a record": 125,
            "failed": 610,
            "mapped onto a record": 420,
            "unknown": 982
        ])
    }

    @Test("a thousand outskirts runs reach each antecedent of the dead-code path an exact number of times")
    func deadCodeClasses() throws {
        let counts = try Self.counts(IntegerEdgeGen.outskirts, labels: IntegerEdgesPBT.deadCodeLabels(of:))

        #expect(counts == [
            "a field at 0": 416, "a field at Int.max": 416, "failed": 416, "mapped onto a record": 189, "unknown": 570
        ])
    }

    @Test("a thousand pairs of timing lines reach each antecedent of the timing path an exact number of times")
    func timingClasses() throws {
        let counts = try Self.counts(IntegerEdgeGen.timings, labels: IntegerEdgesPBT.timingLabels(of:))

        #expect(counts == [
            "a field at 0": 550, "a field at Int.max": 561, "failed": 765, "mapped onto a record": 129, "unknown": 641
        ])
    }
}
