//
//  ValueShapeAnalyzer.swift
//  SwiftStatsCore
//
//  Whether a function computes a value rather than changing state (PRD
//  §7.10). SwiftEffectInference's `pure` never checks mutation: a visitor
//  that appends to `self`'s issue list is `pure`. So the side-effect signals
//  also ask, from syntax alone, whether the function returns a value and
//  writes nothing outside its own parameters and locals. A write is the
//  target of an assignment, or a call whose value is thrown away, rooted at
//  `self`, `super` or a name the function doesn't bind where the write is.
//

import SwiftSyntax

/// Decides whether a `func` is value-shaped.
enum ValueShapeAnalyzer {
    /// Unqualified calls that check or trap rather than write.
    static let exemptCalls: Set<String> = [
        "assert", "assertionFailure", "fatalError", "precondition", "preconditionFailure"
    ]
    /// Return types that carry no value.
    private static let valuelessReturns: Set<String> = ["()", "Never", "Swift.Never", "Swift.Void", "Void"]

    /// Whether `function` returns a value, takes no `inout`, isn't
    /// `mutating`, and writes no state outside its own bindings.
    static func isValueShaped(_ function: FunctionDeclSyntax) -> Bool {
        guard let body = function.body,
              returnsValue(function),
              function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) }) == false,
              function.signature.parameterClause.parameters.contains(where: isInout) == false else {
            return false
        }
        let parameters = function.signature.parameterClause.parameters.map { parameter in
            (parameter.secondName ?? parameter.firstName).text
        }
        let finder = StateWriteFinder(parameters: Set(parameters), bindings: BindingCollector.scopes(in: body))
        finder.walk(body)
        return finder.writesState == false
    }

    /// Whether `function` declares a return type that carries a value.
    static func returnsValue(_ function: FunctionDeclSyntax) -> Bool {
        guard let returnType = function.signature.returnClause?.type else {
            return false
        }
        return valuelessReturns.contains(compactText(returnType)) == false
    }

    /// `node`'s text without comments or whitespace.
    static func compactText(_ node: some SyntaxProtocol) -> String {
        CanonicalText.render(node).filter { $0.isWhitespace == false }
    }

    /// Whether `item`'s value is the value of the code around it: the only
    /// statement of a getter, a value-returning function, a closure whose
    /// own value is used, or a branch of an `if` or `switch` whose own value
    /// is used.
    static func isReturned(_ item: CodeBlockItemSyntax) -> Bool {
        guard let list = item.parent?.as(CodeBlockItemListSyntax.self), list.count == 1,
              let owner = list.parent else {
            return false
        }
        if owner.is(AccessorBlockSyntax.self) {
            return true
        }
        if let closure = owner.as(ClosureExprSyntax.self) {
            return isClosureValueUsed(closure)
        }
        if owner.is(SwitchCaseSyntax.self) {
            guard let switchExpression = owner.parent?.parent?.as(SwitchExprSyntax.self) else {
                return false
            }
            return isValueUsed(Syntax(switchExpression))
        }
        guard let block = owner.as(CodeBlockSyntax.self), let blockOwner = block.parent else {
            return false
        }
        if let function = blockOwner.as(FunctionDeclSyntax.self) {
            return returnsValue(function)
        }
        if let accessor = blockOwner.as(AccessorDeclSyntax.self) {
            return accessor.accessorSpecifier.tokenKind == .keyword(.get)
        }
        if blockOwner.is(IfExprSyntax.self) {
            return isValueUsed(blockOwner)
        }
        return false
    }

    /// Whether the value of an `if` or `switch` expression is used: it is
    /// anywhere but a statement of its own, unless that statement is returned.
    private static func isValueUsed(_ expression: Syntax) -> Bool {
        var node = expression
        while let parent = node.parent, parent.is(IfExprSyntax.self) || parent.is(ExpressionStmtSyntax.self) {
            node = parent
        }
        if let item = node.parent?.as(CodeBlockItemSyntax.self) {
            return isReturned(item)
        }
        return true
    }

    /// Whether a closure's value is used. Without types the only sign it
    /// isn't is where it is passed: as an argument, trailing closure or
    /// callee of a call that is a statement of its own and isn't returned
    /// (`items.forEach { … }`). Anywhere else (`_ = items.map { … }`, a
    /// call whose value feeds another, a binding) it is used.
    private static func isClosureValueUsed(_ closure: ClosureExprSyntax) -> Bool {
        var node = Syntax(closure)
        while let parent = node.parent, isArgumentWrapper(parent) {
            node = parent
        }
        guard let call = node.parent?.as(FunctionCallExprSyntax.self) else {
            return true
        }
        var statement = Syntax(call)
        while let parent = statement.parent,
              parent.is(TryExprSyntax.self) || parent.is(AwaitExprSyntax.self) || parent.is(ExpressionStmtSyntax.self) {
            statement = parent
        }
        if let item = statement.parent?.as(CodeBlockItemSyntax.self) {
            return isReturned(item)
        }
        return true
    }

    /// Whether `node` holds a call's argument or trailing closure.
    private static func isArgumentWrapper(_ node: Syntax) -> Bool {
        node.is(LabeledExprSyntax.self) || node.is(LabeledExprListSyntax.self)
            || node.is(MultipleTrailingClosureElementSyntax.self)
            || node.is(MultipleTrailingClosureElementListSyntax.self)
    }

    /// Whether `parameter` is `inout`.
    private static func isInout(_ parameter: FunctionParameterSyntax) -> Bool {
        guard let attributed = parameter.type.as(AttributedTypeSyntax.self) else {
            return false
        }
        return attributed.specifiers.contains { specifier in
            specifier.firstToken(viewMode: .sourceAccurate)?.tokenKind == .keyword(.inout)
        }
    }
}
