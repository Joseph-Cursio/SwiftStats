//
//  MutantKey.swift
//  SwiftStatsCore
//
//  What identifies a mutant in SwiftMutator's output (M6, design §2): its
//  path, operator, line, column and occurrence, as `MutantKey` in
//  SwiftMutator's `Results/MutantKey.swift`. The JSON report spells a key
//  `path:line:column Operator`, plus ` (#k)` for occurrence k − 1 > 0; the
//  path may hold spaces and colons, so a spelled key is read from the
//  right, on Unicode scalars (design B23). A number counts only as
//  SwiftMutator prints one: ASCII digits, no sign, no leading zero
//  (decided U11).
//

/// A mutant's key.
struct MutantKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The smallest `k` of a spelled ` (#k)`: occurrence 1, the second
    /// of a place and operator.
    static let firstRepeat = 2
    /// What opens a spelled repeat number, as scalars.
    static let repeatOpen = " (#".unicodeScalars
    /// What closes it.
    static let repeatClose: Unicode.Scalar = ")"
    /// The scalars a spelled number is written in.
    static let digits: ClosedRange<Unicode.Scalar> = "0"..."9"

    /// The path relative to the project SwiftMutator ran in; absolute when
    /// outside it.
    let path: String
    /// The operator's id, such as `RelationalBoundary`.
    let operatorID: String
    /// The 1-based line in the original file.
    let line: Int
    /// The 1-based UTF-8 byte column in the original file, a byte order
    /// mark not counted.
    let column: Int
    /// 0, or n for the nth repeat of the same place and operator in a run.
    let occurrence: Int

    /// The key as SwiftMutator spells it. The repeat number is counted in
    /// `UInt`, so an occurrence of `Int.max`, which a results line may
    /// hold, spells ` (#9223372036854775808)` instead of trapping; that
    /// spelling reads back as no key, as a number outside `Int` should.
    var description: String {
        "\(path):\(line):\(column) \(operatorID)" + (occurrence > 0 ? " (#\(UInt(occurrence) + 1))" : "")
    }

    /// The key of the five parts given.
    init(path: String, operatorID: String, line: Int, column: Int, occurrence: Int) {
        self.path = path
        self.operatorID = operatorID
        self.line = line
        self.column = column
        self.occurrence = occurrence
    }

    /// The key `spelled` spells, read from the right: an optional
    /// ` (#k)` with k ≥ 2, the operator after the last space, then the
    /// column and the line after the last two colons; the rest is the path.
    /// Nil when any part is missing or a number isn't spelled as
    /// SwiftMutator spells one (`number(_:)`, decided U11). The
    /// separators are found among the spelling's Unicode scalars, not its
    /// Characters, so a Prepend scalar just before one, or a combining mark
    /// just after one, stays in its part (design B23, decided U13).
    init?(spelled: String) {
        var rest = Substring(spelled).unicodeScalars
        var repeated = 0
        if rest.last == Self.repeatClose, let open = rest.ranges(of: Self.repeatOpen).last {
            guard let repeatNumber = Self.number(rest[open.upperBound..<rest.index(before: rest.endIndex)]),
                  repeatNumber >= Self.firstRepeat
            else {
                return nil
            }
            repeated = repeatNumber - 1
            rest = rest[..<open.lowerBound]
        }
        guard let space = rest.lastIndex(of: " ") else {
            return nil
        }
        let spelledOperator = rest[rest.index(after: space)...]
        rest = rest[..<space]
        guard spelledOperator.isEmpty == false,
              let columnColon = rest.lastIndex(of: ":"),
              let spelledColumn = Self.number(rest[rest.index(after: columnColon)...])
        else {
            return nil
        }
        rest = rest[..<columnColon]
        guard let lineColon = rest.lastIndex(of: ":"),
              let spelledLine = Self.number(rest[rest.index(after: lineColon)...]),
              lineColon > rest.startIndex
        else {
            return nil
        }
        self.init(
            path: String(Substring(rest[..<lineColon])),
            operatorID: String(Substring(spelledOperator)),
            line: spelledLine,
            column: spelledColumn,
            occurrence: repeated
        )
    }

    /// The positive number `spelled` spells as SwiftMutator prints one:
    /// ASCII digits with no sign and no leading zero, within `Int`. Nil for
    /// anything else, such as `+3`, `0003` or a fullwidth digit;
    /// `Int(_:)` alone reads the first two as 3 (decided U11).
    static func number(_ spelled: Substring.UnicodeScalarView) -> Int? {
        guard let first = spelled.first, first != "0", spelled.allSatisfy(Self.digits.contains) else {
            return nil
        }
        return Int(Substring(spelled))
    }

    /// By path, line, column, operator and occurrence, the order mutants
    /// are listed in.
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.path, lhs.line, lhs.column, lhs.operatorID, lhs.occurrence)
            < (rhs.path, rhs.line, rhs.column, rhs.operatorID, rhs.occurrence)
    }
}
