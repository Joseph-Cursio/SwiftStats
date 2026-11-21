//
//  TestBodyScan.swift
//  SwiftStatsCore
//
//  Walks a test body for assertions and property or idempotency checks
//  (PRD §7.8), noting every callee's base name and every operator used,
//  which link a property test to the suggestions it may check (§7.11),
//  and, to link any test to the public functions it may test (M5), the
//  paths of the names it writes, the members it reads and the calls it
//  makes with their labels (`TestReferences`, `CallReferenceBuilder`).
//  Names are kept without backticks (`` `default` `` is `default`), as
//  records' names are compared.
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
    /// The paths of the names written (`TestReferences.paths`).
    var paths: Set<String> = []
    /// The names read as members (`TestReferences.members`).
    var members: Set<String> = []
    /// The calls, and the unapplied references written with labels
    /// (`CallReference`).
    var calls: Set<CallReference> = []

    /// What the scan found to link tests to public functions.
    var references: TestReferences {
        TestReferences(paths: paths, members: members, calls: calls)
    }

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
        if let call = CallReferenceBuilder.call(node) {
            calls.insert(call)
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
        guard CallReferenceBuilder.isMemberName(node) == false else {
            return .visitChildren
        }
        if case .identifier = node.baseName.tokenKind {
            paths.insert(CallSignature.name(of: node.baseName))
        }
        if CallReferenceBuilder.isCalled(node) == false, let reference = CallReferenceBuilder.reference(node) {
            calls.insert(reference)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let path = CallReferenceBuilder.path(of: ExprSyntax(node))
        if path.isEmpty == false {
            paths.insert(path.joined(separator: "."))
        }
        guard CallReferenceBuilder.isInitialized(node) == false else {
            return .visitChildren
        }
        guard CallReferenceBuilder.isCalled(node) == false else {
            // `box.maker()` may read a property holding a closure and call it.
            if CallReferenceBuilder.isCalledWithoutLabels(node), case .identifier = node.declName.baseName.tokenKind {
                members.insert(CallSignature.name(of: node.declName.baseName))
            }
            return .visitChildren
        }
        if let reference = CallReferenceBuilder.reference(node) {
            calls.insert(reference)
        } else if case .identifier = node.declName.baseName.tokenKind {
            members.insert(CallSignature.name(of: node.declName.baseName))
        }
        return .visitChildren
    }

    override func visit(_ node: KeyPathPropertyComponentSyntax) -> SyntaxVisitorContinueKind {
        if case .identifier = node.declName.baseName.tokenKind {
            members.insert(CallSignature.name(of: node.declName.baseName))
        }
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        if case .identifier = node.name.tokenKind {
            paths.insert(CallSignature.name(of: node.name))
        }
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        let path = CallReferenceBuilder.path(of: TypeSyntax(node))
        if path.isEmpty == false {
            paths.insert(path.joined(separator: "."))
        }
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
