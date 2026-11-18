//
//  TestBodyScan.swift
//  SwiftStatsCore
//
//  Walks a test body for assertions and property or idempotency checks
//  (PRD §7.8).
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
