//
//  MutantKeyPBT+Spellings.swift
//  SwiftStatsCoreTests
//
//  P3.3: any string `MutantKey(spelled:)` accepts re-spells as itself,
//  scalar for scalar, its key in P3.1's domain but for the operator's last
//  scalar, and no string traps; over strings near keys' spellings
//  (`MutantKeyGen+Spelling`), with its examples (recorded spellings with
//  their numbers signed or zero-padded, strings at the edges of what is
//  read, numbers past `Int`) and the meta-test feeding planted defects'
//  readings to its check.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P3.3, its examples and its planted defects.
extension MutantKeyPBT {
    /// P3.3's base runs, over the engine's 100: as cheap as P3.1's, and
    /// each planted defect calibrated fails the law in 4.9 to 7.5 percent
    /// of draws (measured over 200,000 draws: a repeat of 1 accepted, the
    /// rarest, in 4.9; digits folded with wrapping arithmetic in 6.5, or
    /// 5.7 when a negative is refused), so `(1 - 0.049)^300`, about
    /// 3 * 10^-7, is the most a single run misses one (design D14's
    /// 10^-6). `MutantKeyGenTests` counts each branch's flaw alone: a
    /// repeat of 1 in 40 of 1,000 and a number past `Int` in 64.
    static let spellingRuns = 300
    /// What P3.3's tally counts when a spelling is accepted (design D14:
    /// the generator's meta-test counts it in 335 of 1,000 spellings, so
    /// 300 runs never miss it).
    static let accepted = "an accepted spelling"
    /// What P3.3's tally counts when an accepted spelling has a repeat
    /// (design D14: 168 of 1,000, and `(1 - 0.168)^300` is about 10^-24).
    static let acceptedRepeat = "an accepted spelling with a repeat"
    /// What P3.3's tally counts when a spelling is refused (design D14: 665
    /// of 1,000).
    static let refused = "a refused spelling"
    /// The antecedents P3.3 must reach at least once each.
    static let spellingAntecedents = [accepted, acceptedRepeat, refused]
    /// The scalar no operator of an accepted key holds.
    static let space: Unicode.Scalar = " "

    /// Whether `read`, what `MutantKey(spelled:)` read from `text`, and
    /// `respelled`, its spelling, are as P3.3 states: when `text` is
    /// accepted, it re-spells as itself, scalar for scalar, and its key is
    /// in P3.1's domain but for the operator's last scalar: a path that
    /// isn't empty, an operator that isn't empty and holds no space, a
    /// line and a column of at least 1, and an occurrence from 0 to
    /// `Int.max − 1`. A refusal states nothing more. Records an issue for
    /// each law that fails.
    static func checkAccepted(_ text: String, read: MutantKey?, respelled: String?) -> Bool {
        guard let read else {
            return true
        }
        let again = respelled ?? ""
        return holds(
            [
                (
                    again.unicodeScalars.elementsEqual(text.unicodeScalars),
                    "re-spells as itself, not as \(again.debugDescription)"
                ),
                (read.path.isEmpty == false, "reads a path"),
                (
                    read.operatorID.isEmpty == false && read.operatorID.unicodeScalars.contains(space) == false,
                    "reads an operator with no space"
                ),
                (read.line >= 1 && read.column >= 1, "reads a line and a column of at least 1"),
                (read.occurrence >= 0 && read.occurrence < Int.max, "reads an occurrence from 0 to Int.max - 1")
            ],
            subject: "accepting \(text.debugDescription) as " + MutantKeyGen.parts(of: read)
        )
    }

    /// Invariant: any string `MutantKey(spelled:)` accepts re-spells as
    /// itself, scalar for scalar, so it reads as the same key; its key is
    /// in P3.1's domain but for the operator's last scalar; and no string
    /// traps.
    /// Why it holds: `init?(spelled:)`'s doc comment (nil when any part is
    /// missing or a number isn't spelled as SwiftMutator spells one) and
    /// `number(_:)`'s (ASCII digits, no sign, no leading zero, within
    /// `Int`, decided U11), so an accepted string's parts are exactly what
    /// `description` writes back; the repeat's ` (#k)` needs k ≥ 2.
    /// Why it might not: the design's law was "re-spells to a string that
    /// reads as the same key"; since U11 the stronger "re-spells as itself"
    /// holds, and only it detects a sign or a leading zero accepted (`+3`
    /// re-spells as `3`, which reads as the same key). An accepted operator
    /// may end in `)` when no ` (#` comes before it (`a:1:2 x)`). A
    /// refusal states nothing here: P3.1 states which spellings are
    /// accepted. The accepted, accepted-with-a-repeat and refused
    /// antecedents must each fire (the tally).
    /// Oracle: round trip from the string side, plus postconditions;
    /// planted defects: U11's fix undone (`Int(_:)` and `> 0`), ` (#1)`
    /// accepted, an empty path accepted, an empty operator accepted, and
    /// digits folded with wrapping arithmetic (a number past `Int`
    /// accepted), each detected in 20 of 20 calibration runs, and
    /// `Int(_:)` force-unwrapped, detected as a trap.
    /// Tier: Strict (stop-ship).
    @Test(
        "any string read as a key re-spells as itself, its key in the domain, and no string traps",
        .timeLimit(PBTBudget.timeLimit)
    )
    func acceptedSpellingsRespell() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.spellingRuns), input: MutantKeyGen.spelling) { spelling in
            PBTTrace.note(spelling)
            let read = MutantKey(spelled: spelling.text)
            if let read {
                tally.fire(Self.accepted)
                if read.occurrence > 0 {
                    tally.fire(Self.acceptedRepeat)
                }
            } else {
                tally.fire(Self.refused)
            }
            if Self.checkAccepted(spelling.text, read: read, respelled: read?.description) == false {
                PBTTrace.firstFailure(spelling, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.spellingAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        each recorded spelling is accepted and re-spells as itself, and with its line or column signed or \
        zero-padded is refused (decided U11)
        """)
    func recordedSpellingsWithFlaws() throws {
        for spelled in try Self.recordedSpellings() {
            let parts = spelled.split(separator: ":", omittingEmptySubsequences: false)
            let line = parts[parts.count - 2]
            let head = parts.dropLast(2).joined(separator: ":")
            let tail = parts[parts.count - 1]
            let flawed = ["+", "0"].flatMap { mark in
                ["\(head):\(mark)\(line):\(tail)", "\(head):\(line):\(mark)\(tail)"]
            }
            let read = MutantKey(spelled: spelled)

            #expect(read != nil)
            #expect(Self.checkAccepted(spelled, read: read, respelled: read?.description))
            for text in flawed {
                let flawedRead = MutantKey(spelled: text)

                #expect(Self.checkAccepted(text, read: flawedRead, respelled: flawedRead?.description))
                #expect(flawedRead == nil)
            }
        }
    }

    @Test(
        "strings at the edges of what is read are accepted or refused as stated, and an accepted one re-spells",
        arguments: [
            ("Sources/Bar.swift:12:9 SwapTernary (#9223372036854775807)", true),
            ("Sources/Bar.swift:12:9 SwapTernary (#9223372036854775808)", false),
            ("x:1:2 y:3:4:5:6 (#2)", true),
            ("a:1:2 x)", true),
            ("a (#5:1:2 x)", false),
            ("a:1:2 Op(#2)", true),
            (":12:9 SwapTernary", false),
            ("a:1:2 ", false),
            ("a:1:2 Op (#1)", false),
            ("a:1:2 Op (#2) (#3)", false),
            // Past `Int`; read with wrapping arithmetic, these are line 1,
            // column 9, repeat 2 and a negative line.
            ("a:18446744073709551617:9 Op", false),
            ("a:12:18446744073709551625 Op", false),
            ("a:12:9 Op (#18446744073709551618)", false),
            ("a:9223372036854775808:9 Op", false)
        ]
    )
    func edgeSpellings(text: String, isAccepted: Bool) {
        let read = MutantKey(spelled: text)

        #expect(Self.checkAccepted(text, read: read, respelled: read?.description))
        #expect((read != nil) == isAccepted)
    }

    @Test("a planted defect's reading fails P3.3's laws")
    func acceptedDefectsDetected() {
        let signed = "a:+12:9 SwapTernary"
        let padded = "a:12:9 SwapTernary (#02)"
        let lowRepeat = "a:12:9 SwapTernary (#1)"
        let noPath = ":12:9 SwapTernary"
        let noOperator = "a:12:9 "
        let pastInt = "a:18446744073709551617:9 SwapTernary"
        let plain = Self.key("a", "SwapTernary", occurrence: 0)
        let repeated = Self.key("a", "SwapTernary", occurrence: 1)
        let pathless = Self.key("", "SwapTernary", occurrence: 0)
        let operatorless = Self.key("a", "", occurrence: 0)
        let wrapped = MutantKey(path: "a", operatorID: "SwapTernary", line: 1, column: 9, occurrence: 0)

        PlantedDefect.expectDetected("U11's fix undone: a sign accepted", sourceLocation: #_sourceLocation) {
            Self.checkAccepted(signed, read: plain, respelled: plain.description)
        }
        PlantedDefect.expectDetected("U11's fix undone: a leading zero accepted", sourceLocation: #_sourceLocation) {
            Self.checkAccepted(padded, read: repeated, respelled: repeated.description)
        }
        PlantedDefect.expectDetected("a repeat of 1 accepted", sourceLocation: #_sourceLocation) {
            Self.checkAccepted(lowRepeat, read: plain, respelled: plain.description)
        }
        PlantedDefect.expectDetected("an empty path accepted", sourceLocation: #_sourceLocation) {
            Self.checkAccepted(noPath, read: pathless, respelled: pathless.description)
        }
        PlantedDefect.expectDetected("an empty operator accepted", sourceLocation: #_sourceLocation) {
            Self.checkAccepted(noOperator, read: operatorless, respelled: operatorless.description)
        }
        PlantedDefect.expectDetected("a number past Int read wrapped", sourceLocation: #_sourceLocation) {
            Self.checkAccepted(pastInt, read: wrapped, respelled: wrapped.description)
        }
    }
}
