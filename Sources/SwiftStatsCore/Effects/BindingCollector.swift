//
//  BindingCollector.swift
//  SwiftStatsCore
//
//  The names a function body binds, each with where it is visible: a `let`
//  or `var` pattern, a `guard` binding or a local function's name in the
//  rest of its block (the `guard`'s `else` apart); an `if` or `while`
//  condition's binding in that statement (an `if`'s `else` apart); a loop
//  pattern in its `for`; a `case` or `catch` pattern in its clause; a
//  closure's parameters in the closure; a local function's parameters in
//  that function. Swift rejects a use before a same-named declaration in
//  its block, so the whole block can stand for a declaration's scope. A
//  write to a stored property is then still a write when the function also
//  binds that name somewhere else, as `if let pending` does.
//

import SwiftSyntax

/// Collects the names bound in one body, with their scopes.
final class BindingCollector: SyntaxVisitor {
    /// Where a binding is visible: inside `node`, but not inside `hidden`.
    struct Scope: Hashable {
        /// The node the binding is visible in.
        let node: SyntaxIdentifier
        /// A part of `node` it isn't visible in.
        let hidden: SyntaxIdentifier?
    }

    /// The scopes found so far, by name.
    private(set) var scopes: [String: [Scope]] = [:]
    /// The body walked, which stands for any scope not found otherwise.
    private let root: SyntaxIdentifier

    /// Creates a collector for the body `root`.
    init(root: SyntaxIdentifier) {
        self.root = root
        super.init(viewMode: .sourceAccurate)
    }

    /// The names bound anywhere in `body`, each with the scopes it is bound in.
    static func scopes(in body: some SyntaxProtocol) -> [String: [Scope]] {
        let collector = Self(root: body.id)
        collector.walk(body)
        return collector.scopes
    }

    /// Whether `name` is bound, in `scopes`, where `node` is.
    static func isBound(_ name: String, at node: some SyntaxProtocol, in scopes: [String: [Scope]]) -> Bool {
        guard let candidates = scopes[name] else {
            return false
        }
        var ancestors: Set<SyntaxIdentifier> = []
        var current: Syntax? = Syntax(node)
        while let each = current {
            ancestors.insert(each.id)
            current = each.parent
        }
        return candidates.contains { scope in
            ancestors.contains(scope.node) && scope.hidden.map(ancestors.contains) != true
        }
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        bind(node.identifier.text, in: patternScope(of: Syntax(node)))
        return .visitChildren
    }

    override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
        bind(node.name.text, in: closureScope(of: Syntax(node)))
        return .visitChildren
    }

    override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
        bind((node.secondName ?? node.firstName).text, in: closureScope(of: Syntax(node)))
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        bind(node.name.text, in: Scope(node: enclosingBlock(of: Syntax(node)), hidden: nil))
        for parameter in node.signature.parameterClause.parameters {
            bind((parameter.secondName ?? parameter.firstName).text, in: Scope(node: node.id, hidden: nil))
        }
        return .visitChildren
    }

    /// Records that `name` is bound in `scope`.
    private func bind(_ name: String, in scope: Scope) {
        scopes[name, default: []].append(scope)
    }

    /// The scope of a name bound by the pattern `node`.
    private func patternScope(of node: Syntax) -> Scope {
        var current = node
        while let parent = current.parent, current.id != root {
            if let conditions = parent.as(ConditionElementListSyntax.self) {
                return conditionScope(of: conditions)
            }
            if parent.is(ForStmtSyntax.self) || parent.is(SwitchCaseSyntax.self) || parent.is(CatchClauseSyntax.self)
                || parent.is(CodeBlockItemListSyntax.self) || parent.is(MemberBlockItemListSyntax.self) {
                return Scope(node: parent.id, hidden: nil)
            }
            current = parent
        }
        return Scope(node: root, hidden: nil)
    }

    /// The scope of a name bound in the conditions `conditions`.
    private func conditionScope(of conditions: ConditionElementListSyntax) -> Scope {
        guard let statement = conditions.parent else {
            return Scope(node: root, hidden: nil)
        }
        if let ifExpression = statement.as(IfExprSyntax.self) {
            return Scope(node: ifExpression.id, hidden: ifExpression.elseBody?.id)
        }
        if let guardStatement = statement.as(GuardStmtSyntax.self) {
            return Scope(node: enclosingBlock(of: statement), hidden: guardStatement.body.id)
        }
        return Scope(node: statement.id, hidden: nil)
    }

    /// The scope of a parameter of the closure around `node`.
    private func closureScope(of node: Syntax) -> Scope {
        var current = node
        while let parent = current.parent, current.id != root {
            if parent.is(ClosureExprSyntax.self) {
                return Scope(node: parent.id, hidden: nil)
            }
            current = parent
        }
        return Scope(node: root, hidden: nil)
    }

    /// The statements or members `node` is one of, or the body.
    private func enclosingBlock(of node: Syntax) -> SyntaxIdentifier {
        var current = node
        while let parent = current.parent, current.id != root {
            if parent.is(CodeBlockItemListSyntax.self) || parent.is(MemberBlockItemListSyntax.self) {
                return parent.id
            }
            current = parent
        }
        return root
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
