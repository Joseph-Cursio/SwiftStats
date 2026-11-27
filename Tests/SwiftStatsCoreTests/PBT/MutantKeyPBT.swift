import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of a mutant's key as SwiftMutator spells it (M6, design §2,
/// `MutantKey`'s doc comments, decided U11 and U13), over keys in the
/// domain whose spelling reads back and strings near such spellings
/// (`MutantKeyGen`): every key in the domain reads back from its spelling
/// (P3.1), and any string `MutantKey(spelled:)` accepts re-spells as
/// itself, its key in that domain, and none traps (P3.3). The two stand
/// for injectivity, which P3.1 implies. `MutationOutcomeTests` holds the
/// fixed examples; each property here has its own, calling its shared
/// check, and meta-tests that feed a planted defect's output to that check.
@Suite("Mutant keys: properties", .tags(.pbt))
struct MutantKeyPBT {
    /// P3.1's base runs, over the engine's 100: one spelling and one read
    /// cost microseconds and the domain is flat, so more draws cost nothing
    /// and reach more path, operator and number classes.
    static let readBackRuns = 300
    /// The spellings in SwiftMutator's recorded reports: every
    /// `appliedOperators` entry's `key`, in each recorded case's
    /// `report.json`.
    static func recordedSpellings() throws -> [String] {
        let cases = [
            (MutationFixture.coverageDirectory, "full"), (MutationFixture.directory, "full"),
            (MutationFixture.directory, "since"), (MutationFixture.directory, "interrupted"),
            (MutationFixture.directory, "resumed")
        ]
        return try cases.flatMap { fixture, name in
            let data = try MutationFixture.data("report.json", of: name, in: fixture)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let files = object?["fileReports"] as? [[String: Any]] ?? []
            return files
                .flatMap { $0["appliedOperators"] as? [[String: Any]] ?? [] }
                .compactMap { $0["key"] as? String }
        }
    }

    /// Whether `read`, what `MutantKey(spelled:)` read from `key`'s
    /// spelling, is `key`: the same five parts, the path and the operator
    /// scalar for scalar. Records an issue for each law that fails.
    static func checkReadBack(_ key: MutantKey, read: MutantKey?) -> Bool {
        let subject = "the spelling \(key.description.debugDescription)"
        guard let read else {
            return holds([(false, "reads as a key, expected " + MutantKeyGen.parts(of: key))], subject: subject)
        }
        return holds(
            [
                (read == key, "reads as " + MutantKeyGen.parts(of: read) + ", expected " + MutantKeyGen.parts(of: key)),
                (read.path.unicodeScalars.elementsEqual(key.path.unicodeScalars), "keeps the path's scalars"),
                (
                    read.operatorID.unicodeScalars.elementsEqual(key.operatorID.unicodeScalars),
                    "keeps the operator's scalars"
                )
            ],
            subject: subject
        )
    }

    /// Records an issue naming `subject`, in ASCII, for each law in `laws`
    /// that fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record(Comment(rawValue: PBTTrace.ascii("\(subject) fails: it \(law.law)")))
        }
        return laws.allSatisfy(\.holds)
    }

    /// The key of `path`, `operatorID`, line 12, column 9 and
    /// `occurrence`.
    static func key(_ path: String, _ operatorID: String, occurrence: Int) -> MutantKey {
        MutantKey(path: path, operatorID: operatorID, line: 12, column: 9, occurrence: occurrence)
    }

    // MARK: P3.1

    /// Invariant: every key in the domain reads back from its spelling, as
    /// the same five parts, its path and operator scalar for scalar.
    /// Why it holds: `MutantKey`'s header and `init?(spelled:)`'s doc
    /// comment (the spelling is `path:line:column Operator`, plus ` (#k)`
    /// for occurrence k − 1 > 0, read from the right on Unicode scalars, so
    /// a path may hold spaces, colons and ` (#`, and a Prepend scalar or a
    /// combining mark beside a separator stays in its part, B23 and U13;
    /// `description` spells the repeat in `UInt`, step 4a).
    /// Why it might not: the domain is a path that isn't empty, an
    /// operator that isn't empty, holds no space and doesn't end in `)`
    /// (with occurrence 0, a ` (#` before such an operator makes the
    /// spelling read as a repeat: the format is ambiguous there, and
    /// SwiftMutator's operators are identifiers), lines and columns from 1
    /// to `Int.max`, and occurrences up to `Int.max − 1` (`Int.max` spells
    /// a repeat past `Int`, which reads as no key, pinned in
    /// `MutationOutcomeTests`). Injectivity is implied, so P3.3 is its pair.
    /// Oracle: round trip; planted defects: the separators found among
    /// Characters (B23's fix undone), the path split at its first colon,
    /// occurrence 1 spelled with no repeat, ` (#2)` refused, and any number
    /// holding a zero refused (an over-eager U11 fix), each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "every key in the domain reads back from its spelling, its path and operator scalar for scalar",
        .timeLimit(PBTBudget.timeLimit)
    )
    func keysReadBack() async {
        let latch = FirstFailureLatch()
        await propertyCheck(count: PBTBudget.runs(Self.readBackRuns), input: MutantKeyGen.keyInput) { input in
            PBTTrace.note(input)
            if Self.checkReadBack(input.key, read: MutantKey(spelled: input.key.description)) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
    }

    @Test("every key SwiftMutator's recorded reports spell reads back, and is spelled as recorded")
    func recordedKeysReadBack() throws {
        let spellings = try Self.recordedSpellings()

        #expect(spellings.count == 140)
        for spelled in spellings {
            guard let key = MutantKey(spelled: spelled) else {
                Issue.record("the recorded spelling \(spelled.debugDescription) reads as no key")
                continue
            }
            #expect(Self.checkReadBack(key, read: MutantKey(spelled: key.description)))
            #expect(key.description == spelled)
        }
    }

    @Test("""
        a key at the domain's edges reads back: a Prepend scalar before the line's colon, an operator holding a \
        colon and (# between a combining mark and a Prepend scalar, the largest line, and the largest occurrence
        """)
    func edgeKeyReadsBack() {
        let key = MutantKey(
            path: "Sources/Bar.swift\u{600}",
            operatorID: "\u{301}Swap:(#2\u{6DD}",
            line: Int.max,
            column: 1,
            occurrence: Int.max - 1
        )

        #expect(Self.checkReadBack(key, read: MutantKey(spelled: key.description)))
        // Compared with the Prepend scalar: it joins the space after it into
        // one Character.
        #expect(key.description.hasSuffix("\u{6DD} (#9223372036854775807)"))
    }

    @Test("a path holding colons, spaces, a repeat, a place and a line break reads back, its repeat holding a zero")
    func oddPathReadsBack() {
        let key = MutantKey(
            path: "My Sources/a:b (#3).swift:12:9 X\n\u{1F1EF}\u{1F1F5}",
            operatorID: "RelationalBoundary",
            line: 100,
            column: 10,
            occurrence: 9
        )

        #expect(Self.checkReadBack(key, read: MutantKey(spelled: key.description)))
        #expect(key.description.hasSuffix(":100:10 RelationalBoundary (#10)"))
    }

    @Test("""
        outside the domain, an operator ending in ")" after a path holding " (#" spells ambiguously and reads as \
        no key, and the generator never draws such an operator
        """)
    func ambiguousSpelling() {
        let key = MutantKey(path: "a (#5", operatorID: "x)", line: 1, column: 2, occurrence: 0)

        #expect(key.description == "a (#5:1:2 x)")
        #expect(MutantKey(spelled: key.description) == nil)
        #expect(MutantKeyGen.admissible("x)") == "x)_")
        #expect(MutantKeyGen.admissible("a b") == "a_b")
    }

    @Test("a planted defect's reading fails P3.1's law")
    func readBackDefectsDetected() {
        let key = MutantKey(path: "x\u{600}:y", operatorID: "Op", line: 12, column: 9, occurrence: 1)
        let firstColon = MutantKey(path: "x\u{600}", operatorID: "Op", line: 0, column: 9, occurrence: 1)
        let noRepeat = MutantKey(path: "x\u{600}:y", operatorID: "Op", line: 12, column: 9, occurrence: 0)
        let decomposed = Self.key("Sources/Cafe\u{301}.swift", "SwapTernary", occurrence: 0)
        let composed = Self.key("Sources/Caf\u{E9}.swift", "SwapTernary", occurrence: 0)

        PlantedDefect.expectDetected("the separators found among Characters", sourceLocation: #_sourceLocation) {
            Self.checkReadBack(key, read: nil)
        }
        PlantedDefect.expectDetected("the path split at its first colon", sourceLocation: #_sourceLocation) {
            Self.checkReadBack(key, read: firstColon)
        }
        PlantedDefect.expectDetected("occurrence 1 spelled with no repeat", sourceLocation: #_sourceLocation) {
            Self.checkReadBack(key, read: noRepeat)
        }
        PlantedDefect.expectDetected("the path read back composed", sourceLocation: #_sourceLocation) {
            Self.checkReadBack(decomposed, read: composed)
        }
    }
}
