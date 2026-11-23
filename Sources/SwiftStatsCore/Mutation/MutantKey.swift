//
//  MutantKey.swift
//  SwiftStatsCore
//
//  What identifies a mutant in SwiftMutator's output (M6, design §2): its
//  path, operator, line, column and occurrence, as `MutantKey` in
//  SwiftMutator's `Results/MutantKey.swift`. The JSON report spells a key
//  `path:line:column Operator`, plus ` (#k)` for occurrence k − 1 > 0; the
//  path may hold spaces and colons, so a spelled key is read from the
//  right.
//

/// A mutant's key.
struct MutantKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The smallest `k` of a spelled ` (#k)`: occurrence 1, the second
    /// of a place and operator.
    static let firstRepeat = 2

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

    /// The key as SwiftMutator spells it.
    var description: String {
        "\(path):\(line):\(column) \(operatorID)" + (occurrence > 0 ? " (#\(occurrence + 1))" : "")
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
    /// Nil when any part is missing or isn't a positive number.
    init?(spelled: String) {
        var rest = Substring(spelled)
        var repeated = 0
        if rest.hasSuffix(")"), let open = rest.range(of: " (#", options: .backwards) {
            guard let repeatNumber = Int(rest[open.upperBound..<rest.index(before: rest.endIndex)]),
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
              let spelledColumn = Int(rest[rest.index(after: columnColon)...]), spelledColumn > 0
        else {
            return nil
        }
        rest = rest[..<columnColon]
        guard let lineColon = rest.lastIndex(of: ":"),
              let spelledLine = Int(rest[rest.index(after: lineColon)...]), spelledLine > 0,
              lineColon > rest.startIndex
        else {
            return nil
        }
        self.init(
            path: String(rest[..<lineColon]),
            operatorID: String(spelledOperator),
            line: spelledLine,
            column: spelledColumn,
            occurrence: repeated
        )
    }

    /// By path, line, column, operator and occurrence, the order mutants
    /// are listed in.
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.path, lhs.line, lhs.column, lhs.operatorID, lhs.occurrence)
            < (rhs.path, rhs.line, rhs.column, rhs.operatorID, rhs.occurrence)
    }
}
