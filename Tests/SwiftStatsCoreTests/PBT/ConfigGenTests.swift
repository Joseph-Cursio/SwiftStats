import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the configuration generator draws (design D14): from a fixed seed,
/// a thousand texts reach each antecedent of P11.1 an exact number of
/// times (a valid configuration, an empty one after a document start, and
/// one with a collector's `arguments` or swiftmutator's `options` given no
/// value or a two-digit base-60 `workers`; a value spelled oddly, a
/// base-60 `workers` past `Int` among them; a value of another type;
/// `arguments` that aren't `--skip` pairs; unknown or repeated keys; a key
/// that isn't plain text; a section and its alias; text that isn't a
/// configuration; flow style from the top, CRLF line ends, something
/// before the first key), a thousand key faults reach
/// each antecedent of P11.3 (unknown keys at each level, two in one
/// mapping, a key repeated as written, in other quotes, read as two types
/// at the top and nested, a collector named twice), and a thousand of one
/// edge's cases reach each class of P11.2 (the edge, one step outside, far
/// outside, quoted, flow style). Every valid configuration of a
/// thousand reads. The counts hold under this engine's generator code and
/// this standard library; a change to either, or to a weight or list in
/// `ConfigGen`, redraws them. Hand-worked examples pin the drafts'
/// writing and editing, and the bounds' table.
@Suite("Configuration generator")
struct ConfigGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: only a text fragment's scalar rejects
    /// a value (a surrogate), so a few are always enough at this seed.
    static let attempts = 10
    /// The fixed seed the meta-tests draw from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    @Test("a thousand texts reach each antecedent of P11.1 an exact number of times")
    func anyClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let draft = try ConfigGen.anyCase.run(using: &random, limit: Self.attempts)
            for label in ConfigurationPBT.anyLabels(of: draft) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "a base-60 workers past Int": 38,
            "a key that isn't plain text": 71,
            "a section and its alias": 42,
            "a valid configuration": 267,
            "a valid configuration with a two-digit base-60 workers": 55,
            "a valid configuration with arguments given no value": 71,
            "a valid configuration with options given no value": 44,
            "a value of another type": 75,
            "a value spelled oddly": 218,
            "an empty configuration after a document start": 91,
            "an unknown or repeated key": 84,
            "arguments that aren't --skip pairs": 55,
            "flow style from the top": 27,
            "lines ending in CRLF": 167,
            "something before the first key": 285,
            "text that isn't a configuration": 188
        ])
    }

    @Test("a thousand key faults reach each antecedent of P11.3 an exact number of times")
    func keyClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let fault = try ConfigGen.keyFault.run(using: &random, limit: Self.attempts)
            for label in ConfigurationPBT.keyLabels(of: fault) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "a collector named twice": 72,
            "a key read as two types at the top": 19,
            "a key read as two types, nested": 74,
            "a key repeated as written": 185,
            "a key repeated in other quotes, read alike": 260,
            "an unknown key at the top": 121,
            "an unknown key in a collector's entry": 78,
            "an unknown key in swiftmutator's options": 34,
            "an unknown key under history or signals": 72,
            "an unknown key under history.coupling or a signal": 157,
            "two unknown keys in one mapping": 205
        ])
    }

    @Test("a thousand of one edge's cases reach each class of P11.2 an exact number of times")
    func boundClasses() throws {
        let bound = try ConfigurationPBT.bound(named: "hotspot threshold at most 100")
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let draft = try ConfigGen.boundCase(bound).run(using: &random, limit: Self.attempts)
            for label in ConfigurationPBT.boundLabels(of: draft) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "a quoted value": 675,
            "a value in flow style": 162,
            "far outside": 323,
            "one step outside": 346,
            "the edge": 331
        ])
    }

    @Test("every valid configuration of a thousand reads")
    func validDraftsRead() throws {
        var random = Self.seeded
        for _ in 0..<Self.draws {
            let members = try ConfigGen.valid.run(using: &random, limit: Self.attempts)
            let layout = try ConfigGen.layout.run(using: &random, limit: Self.attempts)
            let text = layout.text(of: members)

            #expect(throws: Never.self, "\(text.debugDescription)") {
                try SwiftStatsConfiguration.parse(text, path: ConfigurationPBT.file)
            }
        }
    }

    @Test("a draft is written in block style above its flow depth and in flow style from it, scalars as YAML needs")
    func draftsWritten() {
        let members = [
            YAMLDraft.member("history", .mapping([YAMLDraft.member("window", .text("1d"))])),
            YAMLDraft.member("excluded", .sequence([.text("**/x"), .scalar("it's", .single), .text("a b")])),
            YAMLDraft.member("collectors", .mapping([YAMLDraft.member("swiftlint", nil)]))
        ]

        #expect(YAMLDraft.document(members, flowDepth: ConfigGen.blockDepth) == """
            history:
              window: 1d
            excluded:
              - "**/x"
              - 'it''s'
              - a b
            collectors:
              swiftlint:

            """)
        #expect(YAMLDraft.document(members, flowDepth: 1) == """
            history: {window: 1d}
            excluded: ["**/x", 'it''s', a b]
            collectors: {swiftlint: ~}

            """)
        #expect(YAMLDraft.document(members, flowDepth: 0)
            == "{history: {window: 1d}, excluded: [\"**/x\", 'it''s', a b], collectors: {swiftlint: ~}}\n")
        #expect(YAMLText.doubleQuoted("a\"\\\t\u{0}\u{85}\u{2028}\u{FEFF}\u{1F600}\u{E9}")
            == "\"a\\\"\\\\\\t\\u0000\\u0085\\u2028\\uFEFF\u{1F600}\u{E9}\"")
        #expect(YAMLDraft.written("a\nb", quote: .single) == "\"a\\u000Ab\"")
    }

    @Test("""
        only text YAML reads back plain as itself is written plain: no indicator first (but - before a \
        character), no flow indicator, no ': ' or ' #', no colon or space at an end, nothing unprintable
        """)
    func plainSafety() {
        let plain = ["a", "1:30", "-5e-324", "a b", "x:y", "\\bfix\\b", "\u{E9}", "<<", "a#b"]
        let quoted = [
            "", "-", "- a", "*x", "#x", "[x-z]+", "a, b", "a: b", "a #b", "a:", " a", "a ", "a\tb", "a\nb", "---x"
        ]

        for text in plain {
            #expect(YAMLText.isPlainSafe(text), "\(text.debugDescription)")
        }
        for text in quoted {
            #expect(YAMLText.isPlainSafe(text) == false, "\(text.debugDescription)")
        }
        #expect(YAMLText.isPlainSafe("#\u{301}") == false)
    }

    @Test("an edit sets, removes and adds members at a path, making the mappings missing on the way")
    func draftsEdited() {
        let start = [YAMLDraft.member("signals", .mapping([YAMLDraft.member("hotspot", nil)]))]
        let set = YAMLDraft.setting(.text("5"), at: ["signals", "hotspot", "threshold"], in: start)
        let made = YAMLDraft.setting(.text("2"), at: ["collectors", "swiftmutator", "options", "workers"], in: set)
        let added = YAMLDraft.inserting(YAMLDraft.member("x", .text("1")), at: 0, under: ["signals"], in: made)
        let removed = YAMLDraft.removing(at: ["signals", "hotspot"], in: added)

        #expect(YAMLDraft.document(set, flowDepth: 0) == "{signals: {hotspot: {threshold: 5}}}\n")
        #expect(YAMLDraft.document(made, flowDepth: 1)
            == "signals: {hotspot: {threshold: 5}}\ncollectors: {swiftmutator: {options: {workers: 2}}}\n")
        #expect(YAMLDraft.members(at: ["signals"], in: added).compactMap(\.key.keyText) == ["x", "hotspot"])
        #expect(YAMLDraft.members(at: ["signals"], in: removed).compactMap(\.key.keyText) == ["x"])
    }

    @Test("""
        each edge's value outside is one step past it, a day, one, or the next Double, the right way, and its far \
        value lies beyond that
        """)
    func boundsStepOnce() {
        for bound in ConfigBounds.all {
            let isDays = bound.edge.hasSuffix("d")
            let edge = Double(isDays ? String(bound.edge.dropLast()) : bound.edge) ?? .nan
            let outside = Double(isDays ? String(bound.outside.dropLast()) : bound.outside) ?? .nan
            let far = Double(isDays ? String(bound.far.dropLast()) : bound.far) ?? .nan
            let isWhole = isDays || (Int(bound.edge) != nil && Int(bound.outside) != nil)
            let steps = isWhole ? [edge - 1, edge + 1] : [edge.nextDown, edge.nextUp]

            #expect(steps.contains(outside), "\(bound.name)")
            #expect(outside < edge ? far < outside : far > outside, "\(bound.name)")
        }
        #expect(ConfigBounds.all.count == 41)
    }
}
