//
//  TestBodyScan.swift
//  SwiftStatsCore
//
//  Walks a test body for assertions and property or idempotency checks
//  (PRD §7.8), noting every callee's base name and every operator used,
//  which link a property test to the suggestions it may check (§7.11),
//  and every name the body refers to and every type it calls, which link
//  any test to the public functions it may test (M5).
//

import SwiftSyntax

/// Walks a test body for assertions and property or idempotency checks.
final class TestBodyScan: SyntaxVisitor {
    /// `#expect`, `#require` and `XCTAssert…` calls.
    var assertions = 0
    /// Whether a property check is called.
    var isProperty = false
    /// Whether an idempotency check is called.
    var isIdempotency = false
    /// Trials of the `propertyCheck` calls; nil when there are none.
    var trials: Int?
    /// Whether a `propertyCheck` call's `count:` isn't a literal.
    var hasUnreadableTrials = false
    /// The base names of the functions called, for `f(…)` and `x.f(…)`,
    /// and the operators used, infix, prefix or postfix.
    var callees: Set<String> = []
    /// The names referred to: each identifier read, called or reached as a
    /// member (`x`, `f(…)`, `x.count`, `\.count`) and each type named;
    /// operators are not names.
    var names: Set<String> = []
    /// The names called: `f(…)`, `x.f(…)` and `T<U>(…)` give their base
    /// name, `T.init(…)` and `T<U>.init(…)` give `T`; operators are not
    /// calls.
    var calls: Set<String> = []

    /// The called function's base name, for `f(…)` and `x.f(…)`.
    static func calleeName(_ call: FunctionCallExprSyntax) -> String {
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return ""
    }

    /// The name `call` calls a type by, or that it calls: its callee's base
    /// name, a specialised callee's (`T<U>(…)`), or for `T.init(…)` and
    /// `T<U>.init(…)` the base's last name; empty when it has none.
    static func calledName(_ call: FunctionCallExprSyntax) -> String {
        let callee = unspecialized(call.calledExpression)
        if let member = callee.as(MemberAccessExprSyntax.self),
           member.declName.baseName.tokenKind == .keyword(.`init`) {
            let base = member.base.map(unspecialized)
            if let reference = base?.as(DeclReferenceExprSyntax.self) {
                return reference.baseName.text
            }
            return base?.as(MemberAccessExprSyntax.self)?.declName.baseName.text ?? ""
        }
        if let reference = callee.as(DeclReferenceExprSyntax.self), case .identifier = reference.baseName.tokenKind {
            return reference.baseName.text
        }
        if let member = callee.as(MemberAccessExprSyntax.self), case .identifier = member.declName.baseName.tokenKind {
            return member.declName.baseName.text
        }
        return ""
    }

    /// `expression` without its generic arguments: `T` for `T<U>`.
    private static func unspecialized(_ expression: ExprSyntax) -> ExprSyntax {
        expression.as(GenericSpecializationExprSyntax.self)?.expression ?? expression
    }

    /// Whether `name` is a SwiftPropertyLaws `check…PropertyLaws` function.
    static func isPropertyLawCheck(_ name: String) -> Bool {
        name.hasPrefix("check") && name.hasSuffix("PropertyLaws")
    }

    /// Whether `call` is `SwiftPropertyBasedBackend().check(…)`.
    static func isBackendCheck(_ call: FunctionCallExprSyntax) -> Bool {
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "check",
              let base = member.base?.as(FunctionCallExprSyntax.self) else {
            return false
        }
        return calleeName(base) == "SwiftPropertyBasedBackend"
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        switch node.macroName.text {
        case "expect", "require":
            assertions += 1

        case "assertIdempotent":
            isIdempotency = true

        default:
            break
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let name = Self.calleeName(node)
        if name.isEmpty == false {
            callees.insert(name)
        }
        let called = Self.calledName(node)
        if called.isEmpty == false {
            calls.insert(called)
        }
        if name.hasPrefix("XCTAssert") {
            assertions += 1
        } else if name == "assertIdempotentEffects" {
            isIdempotency = true
        } else if TestFacts.propertyCalls.contains(name) || Self.isPropertyLawCheck(name) || Self.isBackendCheck(node) {
            isProperty = true
            if name == "propertyCheck" {
                addTrials(node)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if case .identifier = node.baseName.tokenKind {
            names.insert(node.baseName.text)
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        callees.insert(node.operator.text)
        return .visitChildren
    }

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        callees.insert(node.operator.text)
        return .visitChildren
    }

    override func visit(_ node: PostfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        callees.insert(node.operator.text)
        return .visitChildren
    }

    /// Adds a `propertyCheck` call's trials: its `count:` literal, or the default.
    private func addTrials(_ call: FunctionCallExprSyntax) {
        guard let count = call.arguments.first(where: { $0.label?.text == "count" }) else {
            trials = (trials ?? 0) + TestFacts.defaultTrials
            return
        }
        if let literal = count.expression.as(IntegerLiteralExprSyntax.self),
           let value = Int(literal.literal.text.replacingOccurrences(of: "_", with: "")) {
            trials = (trials ?? 0) + value
        } else {
            hasUnreadableTrials = true
        }
    }

    deinit {
        // Nothing to release: the scan holds only counts.
    }
}
