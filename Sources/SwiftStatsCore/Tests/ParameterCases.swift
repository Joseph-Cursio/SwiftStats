//
//  ParameterCases.swift
//  SwiftStatsCore
//
//  How many cases `@Test(arguments:)` runs, when the arguments are literal
//  (PRD §7.8): one collection runs each element; two run every pair; `zip`
//  runs the shorter's count.
//

import SwiftSyntax

/// Counts a parameterized test's cases.
enum ParameterCases {
    /// The collections `zip` pairs.
    private static let zipArity = 2
    /// A range's parts: lower bound, operator, upper bound.
    private static let rangeParts = 3
    /// The cases `attribute` runs, or nil when it has no `arguments:`, a
    /// collection's size can't be read from the source, or the count
    /// overflows `Int`.
    static func count(in attribute: AttributeSyntax) -> Int? {
        guard case .argumentList(let list) = attribute.arguments,
              let start = list.firstIndex(where: { $0.label?.text == "arguments" }) else {
            return nil
        }
        let collections = list[start...].map(\.expression)
        var total = 1
        for collection in collections {
            guard let size = size(of: collection) else {
                return nil
            }
            let (product, overflow) = total.multipliedReportingOverflow(by: size)
            guard overflow == false else {
                return nil
            }
            total = product
        }
        return total
    }

    /// Whether `attribute` passes `arguments:`.
    static func isParameterized(_ attribute: AttributeSyntax) -> Bool {
        guard case .argumentList(let list) = attribute.arguments else {
            return false
        }
        return list.contains { $0.label?.text == "arguments" }
    }

    /// The number of elements `expression` holds, when the source says.
    static func size(of expression: ExprSyntax) -> Int? {
        if let array = expression.as(ArrayExprSyntax.self) {
            return array.elements.count
        }
        if let dictionary = expression.as(DictionaryExprSyntax.self) {
            if case .elements(let elements) = dictionary.content {
                return elements.count
            }
            return 0
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "zip" {
            let sizes = call.arguments.compactMap { size(of: $0.expression) }
            guard call.arguments.count == zipArity, sizes.count == zipArity else {
                return nil
            }
            return sizes.min()
        }
        if let parenthesized = expression.as(TupleExprSyntax.self), parenthesized.elements.count == 1,
           let only = parenthesized.elements.first {
            return size(of: only.expression)
        }
        return rangeSize(expression)
    }

    /// The size of an integer-literal range `a...b` or `a..<b`, or nil when
    /// it overflows `Int`. The parser leaves operators unfolded, so the
    /// range is a three-element sequence.
    private static func rangeSize(_ expression: ExprSyntax) -> Int? {
        let parts: [ExprSyntax]
        if let sequence = expression.as(SequenceExprSyntax.self) {
            parts = Array(sequence.elements)
        } else if let infix = expression.as(InfixOperatorExprSyntax.self) {
            parts = [infix.leftOperand, infix.operator, infix.rightOperand]
        } else {
            return nil
        }
        guard parts.count == rangeParts,
              let operation = parts[1].as(BinaryOperatorExprSyntax.self),
              let lower = parts.first.flatMap(integer),
              let upper = parts.last.flatMap(integer) else {
            return nil
        }
        let isClosed: Bool
        switch operation.operator.text {
        case "...":
            isClosed = true

        case "..<":
            isClosed = false

        default:
            return nil
        }
        let (difference, overflow) = upper.subtractingReportingOverflow(lower)
        guard overflow == false else {
            return nil
        }
        guard isClosed, difference >= 0 else {
            return max(0, difference)
        }
        let (size, sizeOverflow) = difference.addingReportingOverflow(1)
        return sizeOverflow ? nil : size
    }

    /// The value of an integer literal, negative ones included.
    private static func integer(_ expression: ExprSyntax) -> Int? {
        if let literal = expression.as(IntegerLiteralExprSyntax.self) {
            return Int(literal.literal.text.replacingOccurrences(of: "_", with: ""))
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "-" {
            return integer(prefix.expression).map { -$0 }
        }
        return nil
    }
}
