//
//  MarkerCollector.swift
//  SwiftStatsCore
//
//  The risk markers SwiftStats finds itself, because no SwiftProjectLint
//  rule covers them (PRD §7.4): implicitly unwrapped optionals,
//  `precondition` calls, `unsafe` expressions, `@MainActor` declarations and
//  `Task` creation sites. Each is a finding of the `swiftstats` tool.
//

import SwiftSyntax

/// Finds SwiftStats' own markers in one file.
final class MarkerCollector: SyntaxVisitor {
    /// The tool name on SwiftStats' own findings.
    static let tool = "swiftstats"
    /// Attributes that expand into property tests.
    static let propertyTestMacros: Set<String> = [
        "CheckProperty", "DefensiveCopyTests", "InteractionInvariantTests", "PropertyLawSuite",
        "StableIdentityTests", "ValueSemanticTests"
    ]

    /// Markers found so far, in source order.
    private(set) var markers: [RawFinding] = []

    /// The file being walked.
    private let context: FileContext

    /// Creates a collector for the file described by `context`.
    init(context: FileContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    /// Walks `tree` and returns its markers.
    static func collect(_ tree: SourceFileSyntax, context: FileContext) -> [RawFinding] {
        let collector = Self(context: context)
        collector.walk(tree)
        return collector.markers
    }

    /// Whether `call` creates a task: `Task { … }` or `Task(…) { … }`,
    /// optionally specialised (`Task<Void, Never> { … }`), with a closure.
    static func isTaskCreation(_ call: FunctionCallExprSyntax) -> Bool {
        var callee = ExprSyntax(call.calledExpression)
        if let specialized = callee.as(GenericSpecializationExprSyntax.self) {
            callee = specialized.expression
        }
        guard callee.as(DeclReferenceExprSyntax.self)?.baseName.text == "Task" else {
            return false
        }
        return call.trailingClosure != nil
            || call.arguments.contains { $0.expression.is(ClosureExprSyntax.self) }
    }

    /// Whether `call` calls `precondition` or `Swift.precondition`.
    static func isPrecondition(_ call: FunctionCallExprSyntax) -> Bool {
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == "precondition"
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text == "precondition"
                && member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Swift"
        }
        return false
    }

    /// Whether `attribute` is written on a declaration, directly or inside
    /// an `#if` in its attribute list.
    static func isOnDeclaration(_ attribute: AttributeSyntax) -> Bool {
        var node = attribute.parent
        while let current = node {
            let isListOrCondition = current.is(AttributeListSyntax.self) || current.is(IfConfigClauseSyntax.self)
                || current.is(IfConfigClauseListSyntax.self) || current.is(IfConfigDeclSyntax.self)
            guard isListOrCondition else {
                return current.is(DeclSyntax.self)
            }
            node = current.parent
        }
        return false
    }

    override func visit(_ node: ImplicitlyUnwrappedOptionalTypeSyntax) -> SyntaxVisitorContinueKind {
        add("implicitlyUnwrappedOptional", kind: .defect, at: Syntax(node), message: "implicitly unwrapped optional")
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if Self.isPrecondition(node) {
            add("precondition", kind: .census, at: Syntax(node), message: "precondition")
        } else if Self.isTaskCreation(node) {
            add("taskCreation", kind: .census, at: Syntax(node), message: "Task created")
        }
        return .visitChildren
    }

    override func visit(_ node: UnsafeExprSyntax) -> SyntaxVisitorContinueKind {
        add("unsafeExpression", kind: .census, at: Syntax(node), message: "unsafe expression")
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let name = CanonicalText.render(node.attributeName)
        if name == "MainActor", Self.isOnDeclaration(node) {
            add("mainActorDeclaration", kind: .census, at: Syntax(node), message: "@MainActor declaration")
        } else if Self.propertyTestMacros.contains(name) {
            add("propertyTestMacro", kind: .census, at: Syntax(node), message: "@\(name) expands into property tests")
        } else if name == "IdempotencyTests" {
            let message = "@IdempotencyTests expands into tests"
            add("idempotencyTestMacro", kind: .census, at: Syntax(node), message: message)
        }
        return .visitChildren
    }

    /// Records a marker at `node`'s first token.
    private func add(_ rule: String, kind: FindingKind, at node: Syntax, message: String) {
        let position = context.position(context.converter.location(for: node.positionAfterSkippingLeadingTrivia))
        markers.append(RawFinding(
            tool: Self.tool,
            rule: rule,
            category: nil,
            kind: kind,
            severity: kind == .defect ? "warning" : "info",
            message: message,
            symbol: nil,
            places: [RawFinding.Place(file: context.file, line: position.line, column: position.column)]
        ))
    }

    deinit {
        // Nothing to release: the collector holds only value types.
    }
}
