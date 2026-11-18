//
//  DeclarationCollector.swift
//  SwiftStatsCore
//
//  Collects the declarations the API surface counts (PRD §7.5): types,
//  typealiases, functions, initialisers, subscripts and each name a `var` or
//  `let` binds, outside function bodies and top-level statements (whose
//  declarations are locals). Protocol requirements take their protocol's
//  access and aren't counted; enum cases can't write one.
//

import SwiftSyntax

/// Collects one file's API declarations.
final class DeclarationCollector: SyntaxVisitor {
    /// What encloses the declarations being visited.
    private struct Scope {
        /// The level an unmodified member gets (`internal`, or an extension's).
        let defaultLevel: AccessLevel
        /// Whether that default came from an extension's modifier.
        let defaultIsWritten: Bool
        /// The most visible level a member can have here.
        let cap: AccessLevel
    }

    /// Whether a declaration is a class, and a `final` one.
    enum ClassFinality {
        case final
        case nonFinal
        case notAClass
    }

    /// Declarations found so far, in source order.
    private(set) var declarations: [APIDeclaration] = []

    /// The module being walked.
    private let module: String
    /// Enclosing scopes, outermost first.
    private var scopes = [Scope(defaultLevel: .internal, defaultIsWritten: false, cap: .open)]

    /// Creates a collector for a file of `module`.
    init(module: String) {
        self.module = module
        super.init(viewMode: .sourceAccurate)
    }

    /// Walks `tree` and returns its API declarations.
    static func collect(_ tree: SourceFileSyntax, module: String) -> [APIDeclaration] {
        let collector = Self(module: module)
        collector.walk(tree)
        return collector.declarations
    }

    /// The names `pattern` binds: one for an identifier, those of each
    /// element for a tuple (its labels bind nothing), none for `_`.
    static func boundNames(in pattern: PatternSyntax) -> Int {
        if pattern.is(IdentifierPatternSyntax.self) {
            return 1
        }
        guard let tuple = pattern.as(TuplePatternSyntax.self) else {
            return 0
        }
        return tuple.elements.reduce(0) { $0 + boundNames(in: $1.pattern) }
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.modifiers, node: Syntax(node), finality: .notAClass)
    }

    override func visitPost(_: StructDeclSyntax) {
        scopes.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let isFinal = node.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
        return enterType(node.modifiers, node: Syntax(node), finality: isFinal ? .final : .nonFinal)
    }

    override func visitPost(_: ClassDeclSyntax) {
        scopes.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.modifiers, node: Syntax(node), finality: .notAClass)
    }

    override func visitPost(_: EnumDeclSyntax) {
        scopes.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.modifiers, node: Syntax(node), finality: .notAClass)
    }

    override func visitPost(_: ActorDeclSyntax) {
        scopes.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.modifiers, node: Syntax(node), finality: .notAClass)
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let current = scopes[scopes.count - 1]
        if let written = AccessLevel.written(in: node.modifiers) {
            // Members of a `private` extension are `fileprivate`.
            let level = max(written, .fileprivate)
            scopes.append(Scope(defaultLevel: level, defaultIsWritten: true, cap: min(current.cap, level)))
        } else {
            scopes.append(Scope(defaultLevel: .internal, defaultIsWritten: false, cap: current.cap))
        }
        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        scopes.removeLast()
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.modifiers, node: Syntax(node), finality: .notAClass)
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.modifiers, node: Syntax(node), finality: .notAClass)
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.modifiers, node: Syntax(node), finality: .notAClass)
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.modifiers, node: Syntax(node), finality: .notAClass)
        return .skipChildren
    }

    /// A top-level statement (`if`, `for`, `do`, an expression) holds only
    /// locals, so only declarations are walked into.
    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        node.item.is(DeclSyntax.self) ? .visitChildren : .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let names = node.bindings.reduce(0) { $0 + Self.boundNames(in: $1.pattern) }
        for _ in 0..<names {
            add(node.modifiers, node: Syntax(node), finality: .notAClass)
        }
        return .skipChildren
    }

    override func visit(_: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    /// Counts a type and opens its member scope.
    private func enterType(
        _ modifiers: DeclModifierListSyntax,
        node: Syntax,
        finality: ClassFinality
    ) -> SyntaxVisitorContinueKind {
        let access = add(modifiers, node: node, finality: finality)
        // A `private` type's members are visible in its enclosing scope:
        // the whole file when it is at file scope.
        let cap = access == .private && scopes.count == 1 ? AccessLevel.fileprivate : access
        scopes.append(Scope(defaultLevel: .internal, defaultIsWritten: false, cap: cap))
        return .visitChildren
    }

    /// Counts one declaration and returns its effective level.
    @discardableResult
    private func add(_ modifiers: DeclModifierListSyntax, node: Syntax, finality: ClassFinality) -> AccessLevel {
        let scope = scopes[scopes.count - 1]
        let written = AccessLevel.written(in: modifiers)
        let access = min(written ?? scope.defaultLevel, scope.cap)
        declarations.append(APIDeclaration(
            module: module,
            access: access,
            isImplicitlyInternal: written == nil && scope.defaultIsWritten == false && access == .internal,
            isDocumented: DeclarationFacts.hasDocComment(node.leadingTrivia),
            isClass: finality != .notAClass,
            isFinalClass: finality == .final
        ))
        return access
    }

    deinit {
        // Nothing to release: the collector holds only value types.
    }
}
