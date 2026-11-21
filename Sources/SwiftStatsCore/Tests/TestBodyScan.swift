//
//  TestBodyScan.swift
//  SwiftStatsCore
//
//  Walks a test body for assertions and property or idempotency checks
//  (PRD §7.8), noting every callee's base name and every operator used,
//  which link a property test to the suggestions it may check (§7.11),
//  and every name the body refers to and every type it calls, which link
//  any test to the public functions it may test (M5). Names are kept
//  without backticks (`` `default` `` is `default`), as records' names are
//  compared, and an implicit `.init(…)` that initialises an annotated
//  binding (`let gauge: Gauge = .init()`) calls the annotation's type.
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
    /// name, `T.init(…)` and `T<U>.init(…)` give `T`, and `.init(…)` the
    /// type of the binding it initialises, when that is annotated;
    /// operators are not calls.
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
    /// name, a specialised callee's (`T<U>(…)`), for `T.init(…)` and
    /// `T<U>.init(…)` the base's last name, and for an implicit `.init(…)`
    /// the annotated type of the binding it initialises; empty when it has
    /// none. Names are without backticks.
    static func calledName(_ call: FunctionCallExprSyntax) -> String {
        let callee = unspecialized(call.calledExpression)
        if let member = callee.as(MemberAccessExprSyntax.self),
           member.declName.baseName.tokenKind == .keyword(.`init`) {
            guard let base = member.base.map(unspecialized) else {
                return annotatedType(of: call)
            }
            if let reference = base.as(DeclReferenceExprSyntax.self) {
                return name(of: reference.baseName)
            }
            return base.as(MemberAccessExprSyntax.self).map { name(of: $0.declName.baseName) } ?? ""
        }
        if let reference = callee.as(DeclReferenceExprSyntax.self), case .identifier = reference.baseName.tokenKind {
            return name(of: reference.baseName)
        }
        if let member = callee.as(MemberAccessExprSyntax.self), case .identifier = member.declName.baseName.tokenKind {
            return name(of: member.declName.baseName)
        }
        return ""
    }

    /// `token`'s name, without the backticks an escaped identifier is
    /// written with.
    private static func name(of token: TokenSyntax) -> String {
        token.identifier?.name ?? token.text
    }

    /// The type an implicit `.init(…)` builds when it initialises a binding
    /// annotated with it (`let gauge: Gauge = .init()`, an optional of it
    /// included); empty otherwise.
    private static func annotatedType(of call: FunctionCallExprSyntax) -> String {
        guard let clause = call.parent?.as(InitializerClauseSyntax.self),
              let type = clause.parent?.as(PatternBindingSyntax.self)?.typeAnnotation?.type else {
            return ""
        }
        return typeName(of: type)
    }

    /// The last name of `type`, an optional's wrapped type's for an
    /// optional; empty for any other shape.
    private static func typeName(of type: TypeSyntax) -> String {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return typeName(of: optional.wrappedType)
        }
        if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return typeName(of: unwrapped.wrappedType)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return name(of: identifier.name)
        }
        return type.as(MemberTypeSyntax.self).map { name(of: $0.name) } ?? ""
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
            names.insert(Self.name(of: node.baseName))
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        names.insert(Self.name(of: node.name))
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        names.insert(Self.name(of: node.name))
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
