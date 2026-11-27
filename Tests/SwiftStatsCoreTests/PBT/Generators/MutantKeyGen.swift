//
//  MutantKeyGen.swift
//  SwiftStatsCoreTests
//
//  Mutant keys in the domain whose spelling reads back (P3.1), and strings
//  near such spellings (P3.3). SwiftMutator spells a key
//  `path:line:column Operator`, plus ` (#k)` for occurrence k − 1 > 0, and
//  `MutantKey(spelled:)` reads it from the right, on Unicode scalars
//  (design B23, decided U13), taking a number only as SwiftMutator prints
//  one (decided U11). So the domain is: a path that isn't empty, of any
//  scalars (spaces, colons, ` (#`, line breaks, a Prepend scalar just
//  before the line's colon); an operator that isn't empty, holds no space
//  and doesn't end in `)`; a line and a column from 1 to `Int.max`; and an
//  occurrence from 0 to `Int.max − 1`. An operator ending in `)` is left
//  out because, with occurrence 0, a ` (#` anywhere before it makes the
//  spelling read as a repeat (`a (#5:1:2 x)` reads as no key): the format
//  is ambiguous there, and SwiftMutator's operators are identifiers. An
//  occurrence of `Int.max` spells a repeat past `Int`, which reads as no
//  key, as a number outside `Int` should (step 4a). Paths and operators
//  are recorded ones, built from pieces that split or join text, or any
//  fragments; numbers are small, anywhere in range, or an edge. The
//  spellings P3.3 reads are in `MutantKeyGen+Spelling`.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Generators of mutant keys whose spelling reads back, and of strings near
/// such spellings.
enum MutantKeyGen {
    /// A key in P3.1's domain, P3.1's input.
    struct Key: Sendable, CustomTestStringConvertible {
        /// The key.
        let key: MutantKey

        /// The key's spelling and its five parts, in ASCII
        /// (`PBTTrace.ascii`), so a failure's seed reaches the console.
        var testDescription: String {
            PBTTrace.ascii("\(key.description.debugDescription), " + MutantKeyGen.parts(of: key))
        }
    }

    /// The paths of SwiftMutator's recorded reports (`Tests/Fixtures/*/
    /// Recorded/mutation/*/report.json`), and two with the spaces, colons
    /// and ` (#` a path may hold (`MutationOutcomeTests`).
    static let recordedPaths = [
        "Sources/Core/Bounds.swift",
        "Sources/Probe/Bom.swift",
        "Sources/Exe/main.swift",
        "Nested/Helper/Sources/Helper/Helper.swift",
        "/abs/x y.swift",
        "My Sources/a:b (#3).swift"
    ]
    /// The operators of SwiftMutator's recorded reports.
    static let recordedOperators = [
        "SwapTernary",
        "ReplaceReturnValue",
        "RelationalBoundary",
        "RelationalOperatorReplacement",
        "ChangeArithmeticOperator",
        "ChangeLogicalConnector",
        "ReplaceBooleanValue",
        "RemoveSideEffects",
        "NegateConditional"
    ]
    /// Pieces a path is built of: words, separators, digits, ` (#` and
    /// `)`, a Prepend scalar and a combining mark.
    static let pathPieces = [
        "a", "/", "Sources", ".swift", " ", ":", "12", "0", " (#", ")", "#", "x y", "\u{600}", "\u{301}", "\n"
    ]
    /// What a path may end with, just before the line's colon: a Prepend
    /// scalar (B23), or text that looks like a place or a repeat.
    static let pathTails = UnicodeGen.prepend + [":", ":12", ":3:4", " (#2)", " ", "0"]
    /// Operators that split or join text: a combining mark first, a
    /// Prepend scalar last, colons, `(#`, digits, a byte order mark, a line
    /// break and a tab.
    static let oddOperators = [
        "\u{301}SwapTernary",
        "SwapTernary\u{6DD}",
        "x:(#2",
        "(#",
        "#2",
        ":",
        "1:2",
        "a(#2)b",
        "Op\n",
        "\u{FEFF}Op",
        "Op\t"
    ]
    /// What an operator holds in place of a space, and appends when it
    /// would end in `)`.
    static let operatorReplacement = "_"
    /// What a path is when it would be empty, after a shrink dropped all
    /// its fragments (design D7).
    static let fallbackPath = "p"
    /// What an operator is when it would be empty.
    static let fallbackOperator = "Op"
    /// The scalar no operator holds.
    static let space: Unicode.Scalar = " "
    /// The scalar no operator ends with.
    static let closingParenthesis: Unicode.Scalar = ")"
    /// How many pieces or fragments a built path has (assumed: enough for
    /// any two classes to meet, short enough to read when shrunk).
    static let pathLength = 1...6
    /// How many fragments a wide operator has (assumed, as above).
    static let operatorLength = 1...4
    /// The largest small line, column or occurrence (assumed: past any
    /// real file, and past any real count of repeats).
    static let smallNumber = 99_999
    /// The smallest number holding a zero (forced: the radix).
    static let smallestWithZero = 10
    /// The largest occurrence whose spelling reads back (forced: its
    /// ` (#k)` is `Int.max`).
    static let largestOccurrence = Int.max - 1
    /// Edge lines and columns: the smallest, numbers holding a zero, and
    /// the largest.
    static let edgeNumbers = [1, smallestWithZero, smallestWithZero * smallestWithZero, Int.max]
    /// Edge occurrences: the first repeat, those whose spelled number holds
    /// a zero (`(#10)`, `(#100)`), and the largest that reads back.
    static let edgeOccurrences = [1, smallestWithZero - 1, smallestWithZero * smallestWithZero - 1, largestOccurrence]

    /// Weight of recorded paths and operators.
    static let recordedWeight = 3.0
    /// Weight of built paths and wide operators.
    static let builtWeight = 2.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of small numbers.
    static let smallWeight = 3.0
    /// Weight of occurrence 0, the most common.
    static let firstWeight = 4.0
    /// Weight of small occurrences.
    static let smallOccurrenceWeight = 2.0
    /// The share of paths with a tail.
    static let tailRate: Float = 0.3
    /// A path that isn't empty: a recorded one, one built of pieces, or one
    /// of any fragments, sometimes with a tail.
    static let path = zip(
        Gen.frequency(
            (recordedWeight, Pick.element(of: recordedPaths)),
            (builtWeight, Pick.element(of: pathPieces).array(of: pathLength).map { $0.joined() }),
            (builtWeight, UnicodeGen.fragment.array(of: pathLength).map { $0.joined() })
        ),
        Pick.element(of: pathTails).optional(valueRate: tailRate)
    )
    .map { body, tail in
        let text = body + (tail ?? "")
        return text.isEmpty ? fallbackPath : text
    }

    /// An operator in the domain: a recorded one, one of any inline
    /// fragments, or one that splits or joins text.
    static let operatorID = Gen.frequency(
        (recordedWeight, Pick.element(of: recordedOperators)),
        (builtWeight, UnicodeGen.inlineFragment.array(of: operatorLength).map { $0.joined() }),
        (classWeight, Pick.element(of: oddOperators))
    )
    .map(admissible)

    /// A line or a column: small, anywhere from 1 to `Int.max`, or an edge.
    static let number = Gen.frequency(
        (smallWeight, Gen<Int>.value(in: 1...smallNumber)),
        (classWeight, Gen<Int>.value(in: 1...Int.max)),
        (classWeight, Pick.element(of: edgeNumbers))
    )

    /// An occurrence: 0, small, anywhere up to the largest that reads back,
    /// or an edge.
    static let occurrence = Gen.frequency(
        (firstWeight, Gen.always(0)),
        (smallOccurrenceWeight, Gen<Int>.value(in: 1...smallNumber)),
        (classWeight, Gen<Int>.value(in: 0...largestOccurrence)),
        (classWeight, Pick.element(of: edgeOccurrences))
    )

    /// A key in the domain.
    static let key = zip(path, operatorID, number, number, occurrence)
        .map { path, operatorID, line, column, occurrence in
            MutantKey(path: path, operatorID: operatorID, line: line, column: column, occurrence: occurrence)
        }

    /// A key in the domain, as P3.1's input.
    static let keyInput = key.map(Key.init)

    /// `raw` as an operator in the domain: each space written as `_`, an
    /// `_` appended when it ends in `)`, and `Op` when it is empty.
    static func admissible(_ raw: String) -> String {
        let replacement = Array(operatorReplacement.unicodeScalars)
        var scalars = String.UnicodeScalarView(raw.unicodeScalars.flatMap { $0 == space ? replacement : [$0] })
        if scalars.last == closingParenthesis {
            scalars.append(contentsOf: operatorReplacement.unicodeScalars)
        }
        return scalars.isEmpty ? fallbackOperator : String(scalars)
    }

    /// `key`'s five parts, named, each text as a Swift literal.
    static func parts(of key: MutantKey) -> String {
        "path \(key.path.debugDescription), operator \(key.operatorID.debugDescription), "
            + "line \(key.line), column \(key.column), occurrence \(key.occurrence)"
    }
}
