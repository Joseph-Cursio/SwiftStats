//
//  CallReferenceBuilder.swift
//  SwiftStatsCore
//
//  Reads calls, labelled references and chains of names from a test's
//  syntax (M5, `TestReferences`). A callee or a receiver is a name when it
//  is an identifier or a chain of identifiers (`x`, `A.B`). Generic
//  arguments are dropped. `self`, `Self` and `super` are no names: a call
//  written on one of them is written on the enclosing type or instance
//  (`CallReference.Receiver.selfReference`), and `Self(…)`, `Self.init(…)`
//  and `self.init(…)` call the enclosing type's initialiser
//  (`CallReference.enclosingType`). An implicit `.init(…)` builds the
//  annotated type of the binding it initialises
//  (`let gauge: Kit.Gauge? = .init()`), and any other has no type to name.
//

import SwiftSyntax

/// Reads calls and chains of names from syntax.
enum CallReferenceBuilder {
    /// The call `node` writes; nil when its callee is not a name.
    static func call(_ node: FunctionCallExprSyntax) -> CallReference? {
        named(node.calledExpression, shape: .applied(arguments(of: node)), call: node)
    }

    /// The unapplied reference `node` writes with labels (`x.f(a:)`,
    /// `T.init(a:)`); nil without labels.
    static func reference(_ node: MemberAccessExprSyntax) -> CallReference? {
        labelled(node.declName).flatMap { named(ExprSyntax(node), shape: $0, call: nil) }
    }

    /// The unapplied reference `node` writes with labels (`f(a:)`); nil
    /// without labels.
    static func reference(_ node: DeclReferenceExprSyntax) -> CallReference? {
        labelled(node).flatMap { named(ExprSyntax(node), shape: $0, call: nil) }
    }

    /// Whether `node` is a member's name (`x.name`, `\.name`), not a name
    /// written alone.
    static func isMemberName(_ node: DeclReferenceExprSyntax) -> Bool {
        if let member = node.parent?.as(MemberAccessExprSyntax.self) {
            return member.declName.id == node.id
        }
        return node.parent?.is(KeyPathPropertyComponentSyntax.self) == true
    }

    /// Whether `expression` is a call's callee, specialised or not.
    static func isCalled(_ expression: some SyntaxProtocol) -> Bool {
        var node = Syntax(expression)
        if let parent = node.parent, parent.is(GenericSpecializationExprSyntax.self) {
            node = parent
        }
        return node.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id == node.id
    }

    /// Whether `expression` is a call's callee, unspecialised, and the call
    /// labels none of its arguments (`box.maker()`, `box.handler(1) { }`),
    /// as a call of the closure a property holds is written.
    static func isCalledWithoutLabels(_ expression: some SyntaxProtocol) -> Bool {
        guard let call = expression.parent?.as(FunctionCallExprSyntax.self),
              call.calledExpression.id == expression.id else {
            return false
        }
        return call.arguments.allSatisfy { $0.label == nil } && call.additionalTrailingClosures.isEmpty
    }

    /// Whether `expression` is the type an `init` is written on
    /// (`Kit.Crate` in `Kit.Crate.init(…)`), not a member read.
    static func isInitialized(_ expression: some SyntaxProtocol) -> Bool {
        guard let member = expression.parent?.as(MemberAccessExprSyntax.self) else {
            return false
        }
        return member.base?.id == expression.id && member.declName.baseName.tokenKind == .keyword(.`init`)
    }

    /// The chain of names `expression` is (`a.b.c`); empty for any other
    /// expression.
    static func path(of expression: ExprSyntax) -> [String] {
        let bare = unspecialized(expression)
        if let reference = bare.as(DeclReferenceExprSyntax.self) {
            guard case .identifier = reference.baseName.tokenKind else {
                return []
            }
            return [CallSignature.name(of: reference.baseName)]
        }
        guard let member = bare.as(MemberAccessExprSyntax.self),
              let base = member.base,
              case .identifier = member.declName.baseName.tokenKind else {
            return []
        }
        let prefix = path(of: base)
        return prefix.isEmpty ? [] : prefix + [CallSignature.name(of: member.declName.baseName)]
    }

    /// The chain of names `type` is (`A.B`, an optional's wrapped type's
    /// for an optional); empty for any other type.
    static func path(of type: TypeSyntax) -> [String] {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return path(of: optional.wrappedType)
        }
        if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return path(of: unwrapped.wrappedType)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            guard case .identifier = identifier.name.tokenKind else {
                return []
            }
            return [CallSignature.name(of: identifier.name)]
        }
        guard let member = type.as(MemberTypeSyntax.self) else {
            return []
        }
        let base = path(of: member.baseType)
        return base.isEmpty ? [] : base + [CallSignature.name(of: member.name)]
    }

    /// `call`'s arguments: those in parentheses, then its unlabelled
    /// trailing closure, then its labelled ones.
    private static func arguments(of call: FunctionCallExprSyntax) -> [CallArgument] {
        var arguments = call.arguments.map { argument in
            CallArgument(label: argument.label.map(CallSignature.name(of:)), isTrailingClosure: false)
        }
        if call.trailingClosure != nil {
            arguments.append(CallArgument(label: nil, isTrailingClosure: true))
        }
        arguments += call.additionalTrailingClosures.map { closure in
            CallArgument(label: CallSignature.name(of: closure.label), isTrailingClosure: false)
        }
        return arguments
    }

    /// The labels `reference` is written with (nil for `_`) as a labelled
    /// reference's shape; nil when it has none.
    private static func labelled(_ reference: DeclReferenceExprSyntax) -> CallReference.Shape? {
        reference.argumentNames.map { names in
            .labelled(names.arguments.map { $0.name.tokenKind == .wildcard ? nil : CallSignature.name(of: $0.name) })
        }
    }

    /// The call or reference `callee` writes with `shape`; `call` is the
    /// call, whose binding an implicit `.init(…)` initialises.
    private static func named(
        _ callee: ExprSyntax,
        shape: CallReference.Shape,
        call: FunctionCallExprSyntax?
    ) -> CallReference? {
        let bare = unspecialized(callee)
        if let reference = bare.as(DeclReferenceExprSyntax.self) {
            if reference.baseName.tokenKind == .keyword(.Self) {
                return CallReference(
                    name: CallReference.enclosingType,
                    receiver: .bare,
                    isInitializer: false,
                    shape: shape
                )
            }
            guard case .identifier = reference.baseName.tokenKind else {
                return nil
            }
            return CallReference(
                name: CallSignature.name(of: reference.baseName),
                receiver: .bare,
                isInitializer: false,
                shape: shape
            )
        }
        guard let member = bare.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        if member.declName.baseName.tokenKind == .keyword(.`init`) {
            return initializer(member, shape: shape, call: call)
        }
        guard case .identifier = member.declName.baseName.tokenKind else {
            return nil
        }
        let receiver = member.base.map { base -> CallReference.Receiver in
            if isEnclosing(base) || base.is(SuperExprSyntax.self) {
                return .selfReference
            }
            let written = path(of: base)
            return written.isEmpty ? .expression : .path(written)
        } ?? .implicit
        return CallReference(
            name: CallSignature.name(of: member.declName.baseName),
            receiver: receiver,
            isInitializer: false,
            shape: shape
        )
    }

    /// The initialiser call or reference `member` (`T.init`, `.init`)
    /// writes with `shape`, by its type's path; nil when it names no type.
    private static func initializer(
        _ member: MemberAccessExprSyntax,
        shape: CallReference.Shape,
        call: FunctionCallExprSyntax?
    ) -> CallReference? {
        let type: [String]
        if let base = member.base, isEnclosing(base) {
            type = [CallReference.enclosingType]
        } else if let base = member.base {
            type = path(of: base)
        } else {
            type = call.flatMap(annotatedType(of:)).map(path(of:)) ?? []
        }
        guard let name = type.last else {
            return nil
        }
        let qualifier = Array(type.dropLast())
        return CallReference(
            name: name,
            receiver: qualifier.isEmpty ? .bare : .path(qualifier),
            isInitializer: true,
            shape: shape
        )
    }

    /// The type annotating the binding `call` initialises; nil when it
    /// initialises none, or that has none.
    private static func annotatedType(of call: FunctionCallExprSyntax) -> TypeSyntax? {
        call.parent?.as(InitializerClauseSyntax.self)?.parent?.as(PatternBindingSyntax.self)?.typeAnnotation?.type
    }

    /// Whether `expression` is `self` or `Self`, the enclosing instance or
    /// type.
    private static func isEnclosing(_ expression: ExprSyntax) -> Bool {
        let kind = expression.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind
        return kind == .keyword(.self) || kind == .keyword(.Self)
    }

    /// `expression` without its generic arguments: `T` for `T<U>`.
    private static func unspecialized(_ expression: ExprSyntax) -> ExprSyntax {
        expression.as(GenericSpecializationExprSyntax.self)?.expression ?? expression
    }
}
