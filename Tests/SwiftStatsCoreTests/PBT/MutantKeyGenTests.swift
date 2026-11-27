import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the mutant-key generator draws (design D14): from a fixed seed, a
/// thousand keys reach each class P3.1's round trip depends on an exact
/// number of times (recorded and odd paths and operators, a path holding a
/// colon, a space, ` (#` or a line break, a Prepend scalar just before the
/// line's colon, an operator holding a colon or `(#`, the largest line,
/// column and occurrence, occurrence 1, numbers holding a zero), and a
/// thousand spellings reach each antecedent of P3.3 and each refusal
/// branch a planted defect can drop (accepted, with a repeat, refused;
/// each flawed part; a sign or leading zero alone; a repeat of 1 alone; an
/// empty path or operator alone; a number past `Int` alone, and from any
/// source).
/// The counts hold under this engine's generator code and this standard
/// library; a change to either, or to a weight or list in `MutantKeyGen`,
/// redraws them.
@Suite("Mutant key generator")
struct MutantKeyGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: only scalars reject a value (a
    /// surrogate), so a few are always enough at this seed.
    static let attempts = 10
    /// The fixed seed the meta-tests draw from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))
    /// The Prepend scalars the generators draw.
    static let prependScalars = Set(UnicodeGen.prepend.joined().unicodeScalars)
    /// The combining marks the generators draw first in an operator.
    static let marks: Set<Unicode.Scalar> = ["\u{301}", "\u{308}"]

    /// The classes `key` falls in.
    static func labels(of key: MutantKey) -> [String] {
        let path = key.path.unicodeScalars
        let operatorID = key.operatorID.unicodeScalars
        let numbers = [key.line, key.column, key.occurrence + 1].map(String.init)
        return [
            (MutantKeyGen.recordedPaths.contains(key.path), "recorded path"),
            (path.contains(":"), "path holding a colon"),
            (path.contains(" "), "path holding a space"),
            (key.path.contains(" (#"), "path holding a repeat"),
            (path.contains("\n") || path.contains("\r"), "path holding a line break"),
            (path.last.map(prependScalars.contains) == true, "Prepend before the line's colon"),
            (MutantKeyGen.recordedOperators.contains(key.operatorID), "recorded operator"),
            (operatorID.first.map(marks.contains) == true, "operator starting with a combining mark"),
            (operatorID.contains(":"), "operator holding a colon"),
            (key.operatorID.contains("(#"), "operator holding (#"),
            (key.line == Int.max, "largest line"),
            (key.column == Int.max, "largest column"),
            (key.occurrence == 0, "occurrence 0"),
            (key.occurrence == 1, "occurrence 1"),
            (key.occurrence == Int.max - 1, "largest occurrence"),
            (numbers.contains { $0.contains("0") }, "a number holding a zero")
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// The classes `spelling` falls in.
    static func labels(of spelling: MutantKeyGen.Spelling) -> [String] {
        let read = MutantKey(spelled: spelling.text)
        var labels = [read == nil ? "refused" : "accepted"]
        if let read, read.occurrence > 0 {
            labels.append("accepted with a repeat")
        }
        switch spelling.source {
        case .pieces:
            labels.append("pieces")
        case let .key(_, flaws):
            labels.append("\(flaws.count) flaws")
            labels += flaws.map { "flawed \($0.part)" }
            if let flaw = flaws.first, flaws.count == 1 {
                labels += alone(flaw)
            }
        }
        if digitRuns(of: spelling.text).contains(where: isPastInt) {
            labels.append("a number past Int")
        }
        return labels
    }

    /// The labels of `flaw` when it is a spelling's only one, for the
    /// refusal branches a planted defect can drop.
    static func alone(_ flaw: MutantKeyGen.Flaw) -> [String] {
        let number = [.line, .column, .repeatSuffix].contains(flaw.part)
        let body = body(of: flaw)
        let signed = body.hasPrefix("+") || (body.hasPrefix("0") && body.count > 1)
        return [
            (number && signed, "a sign or leading zero alone"),
            (number && isPastInt(body), "a number past Int alone"),
            (flaw.part == .repeatSuffix && flaw.text == " (#1)", "a repeat of 1 alone"),
            (flaw.part == .path, "an empty path alone"),
            (flaw.part == .operatorID && flaw.text.isEmpty, "an empty operator alone")
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// What `flaw` writes, without the ` (#` and `)` around a repeat's
    /// number.
    static func body(of flaw: MutantKeyGen.Flaw) -> Substring {
        let text = Substring(flaw.text)
        guard flaw.part == .repeatSuffix, text.hasPrefix(" (#"), text.hasSuffix(")") else {
            return text
        }
        return text.dropFirst(" (#".count).dropLast()
    }

    /// The longest runs of ASCII digits in `text`, on Unicode scalars: what
    /// `MutantKey.number(_:)` may be handed, whatever the source.
    static func digitRuns(of text: String) -> [Substring] {
        text.unicodeScalars
            .split { ("0"..."9").contains($0) == false }
            .map { Substring($0) }
    }

    /// Whether `text` is ASCII digits for a number past what an `Int` holds.
    static func isPastInt(_ text: Substring) -> Bool {
        text.isEmpty == false && text.allSatisfy { ("0"..."9").contains($0) } && Int(text) == nil
    }

    @Test("a number spelled past Int by 2^64 is 2^64 plus it, for the smallest and largest small numbers")
    func wrappedNumbers() {
        #expect(MutantKeyGen.flawed(1, by: .wrapped) == "18446744073709551617")
        #expect(MutantKeyGen.flawed(MutantKeyGen.smallNumber, by: .wrapped) == "18446744073709651615")
        #expect(MutantKeyGen.flawed(1, by: .overflow) == "9223372036854775808")
    }

    @Test("a thousand keys reach each class P3.1 depends on an exact number of times")
    func keyClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let key = try MutantKeyGen.key.run(using: &random, limit: Self.attempts)
            for label in Self.labels(of: key) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "Prepend before the line's colon": 183,
            "a number holding a zero": 838,
            "largest column": 59,
            "largest line": 57,
            "largest occurrence": 23,
            "occurrence 0": 514,
            "occurrence 1": 28,
            "operator holding (#": 50,
            "operator holding a colon": 74,
            "operator starting with a combining mark": 20,
            "path holding a colon": 240,
            "path holding a line break": 153,
            "path holding a repeat": 149,
            "path holding a space": 368,
            "recorded operator": 522,
            "recorded path": 307
        ])
    }

    @Test("a thousand spellings reach each antecedent of P3.3 and each refusal branch an exact number of times")
    func spellingClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let spelling = try MutantKeyGen.spelling.run(using: &random, limit: Self.attempts)
            for label in Self.labels(of: spelling) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "0 flaws": 320,
            "1 flaws": 520,
            "2 flaws": 46,
            "a number past Int": 117,
            "a number past Int alone": 64,
            "a repeat of 1 alone": 40,
            "a sign or leading zero alone": 69,
            "accepted": 335,
            "accepted with a repeat": 168,
            "an empty operator alone": 55,
            "an empty path alone": 76,
            "flawed column": 91,
            "flawed columnColon": 43,
            "flawed line": 101,
            "flawed lineColon": 38,
            "flawed operatorID": 84,
            "flawed path": 81,
            "flawed repeatSuffix": 133,
            "flawed space": 41,
            "pieces": 114,
            "refused": 665
        ])
    }
}
