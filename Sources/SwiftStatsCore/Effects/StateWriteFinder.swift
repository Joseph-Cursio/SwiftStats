//
//  StateWriteFinder.swift
//  SwiftStatsCore
//
//  Looks for a write outside a function's own bindings (PRD §7.10): the
//  target of `=` or a compound assignment, the receiver of a call whose
//  value is thrown away (`issues.append(x)`, `self.record(…)`,
//  `built[k].append(…)`), or an unqualified thrown-away call that names no
//  local (`addIssue(…)`), when its root is `self`, `super` or an unbound
//  name. Calls on a local `var` are fine, and so are the checks and traps in
//  `ValueShapeAnalyzer.exemptCalls`.
//

import SwiftSyntax

/// Finds writes to state outside a body's bindings.
final class StateWriteFinder: SyntaxVisitor {
    /// Comparison and pattern-match operators that end in `=` but don't assign.
    private static let comparisons: Set<String> = ["!=", "!==", "<=", "==", "===", ">=", "~="]

    /// Whether a write was found.
    private(set) var writesState = false

    /// Names the function binds: its parameters and its locals.
    let bound: Set<String>

    /// Creates a finder that treats `bound` as local.
    init(bound: Set<String>) {
        self.bound = bound
        super.init(viewMode: .sourceAccurate)
    }

    /// Whether `expression` is an assigning operator: `=` or a compound assignment.
    private static func isAssignment(_ expression: ExprSyntax) -> Bool {
        if expression.is(AssignmentExprSyntax.self) {
            return true
        }
        guard let binary = expression.as(BinaryOperatorExprSyntax.self) else {
            return false
        }
        let text = binary.operator.text
        return text.hasSuffix("=") && comparisons.contains(text) == false
    }

    /// The roots of `expression`: the names its member, subscript and call
    /// chains start from, one per element of a tuple. An implicit member
    /// (`.shared`) or a literal has none.
    private static func roots(of expression: ExprSyntax) -> [String] {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return [reference.baseName.text]
        }
        if expression.is(SuperExprSyntax.self) {
            return ["super"]
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.base.map(roots(of:)) ?? []
        }
        if let tuple = expression.as(TupleExprSyntax.self) {
            return tuple.elements.flatMap { roots(of: $0.expression) }
        }
        if let inner = innerExpression(of: expression) {
            return roots(of: inner)
        }
        return []
    }

    /// The expression a wrapper or chain link applies to.
    private static func innerExpression(of expression: ExprSyntax) -> ExprSyntax? {
        if let subscriptCall = expression.as(SubscriptCallExprSyntax.self) {
            return subscriptCall.calledExpression
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            return call.calledExpression
        }
        if let chain = expression.as(OptionalChainingExprSyntax.self) {
            return chain.expression
        }
        if let unwrap = expression.as(ForceUnwrapExprSyntax.self) {
            return unwrap.expression
        }
        if let tryExpression = expression.as(TryExprSyntax.self) {
            return tryExpression.expression
        }
        if let awaitExpression = expression.as(AwaitExprSyntax.self) {
            return awaitExpression.expression
        }
        return nil
    }

    /// The expression a statement consists of, with `try` and `await` removed.
    private static func statementExpression(of item: CodeBlockItemSyntax) -> ExprSyntax? {
        var expression: ExprSyntax
        switch item.item {
        case .expr(let value):
            expression = value

        case .stmt(let statement):
            guard let value = statement.as(ExpressionStmtSyntax.self)?.expression else {
                return nil
            }
            expression = value

        case .decl:
            return nil
        }
        while true {
            if let tryExpression = expression.as(TryExprSyntax.self) {
                expression = tryExpression.expression
            } else if let awaitExpression = expression.as(AwaitExprSyntax.self) {
                expression = awaitExpression.expression
            } else {
                return expression
            }
        }
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated() where index > 0 && Self.isAssignment(element) {
            checkRoots(of: elements[index - 1])
        }
        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if Self.isAssignment(node.operator) {
            checkRoots(of: node.leftOperand)
        }
        return .visitChildren
    }

    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        guard let call = Self.statementExpression(of: node)?.as(FunctionCallExprSyntax.self),
              ValueShapeAnalyzer.isReturned(node) == false else {
            return .visitChildren
        }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            if ValueShapeAnalyzer.exemptCalls.contains(name) == false, isLocal(name) == false {
                writesState = true
            }
        } else {
            checkRoots(of: call.calledExpression)
        }
        return .visitChildren
    }

    /// Notes a write when any root of `expression` isn't local.
    private func checkRoots(of expression: ExprSyntax) {
        if Self.roots(of: expression).contains(where: { isLocal($0) == false }) {
            writesState = true
        }
    }

    /// Whether `name` is bound by the function: a parameter, a local, or a
    /// closure's anonymous parameter (`$0`). `self` and `super` never are.
    private func isLocal(_ name: String) -> Bool {
        guard name != "self", name != "super" else {
            return false
        }
        return name.hasPrefix("$") || bound.contains(name)
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
