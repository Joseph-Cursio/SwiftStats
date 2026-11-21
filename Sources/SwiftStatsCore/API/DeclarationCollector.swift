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
    /// The file being walked.
    private let file: String
    /// The member caps of the types extensions extend.
    private let typeAccess: TypeAccessIndex
    /// Enclosing scopes, outermost first.
    private var scopes = [AccessScope.file]

    /// Creates a collector for `file` of `module`, whose types' member caps
    /// are `typeAccess`.
    init(module: String, file: String, typeAccess: TypeAccessIndex) {
        self.module = module
        self.file = file
        self.typeAccess = typeAccess
        super.init(viewMode: .sourceAccurate)
    }

    /// Walks `tree`, the file `context` describes, and returns its API
    /// declarations; the context's types cap extensions' members, or the
    /// file's own when it has none.
    static func collect(_ tree: SourceFileSyntax, context: FileContext) -> [APIDeclaration] {
        let index = context.typeAccess ?? TypeAccessIndex(files: [(context.file, tree)])
        let collector = Self(module: context.module, file: context.file, typeAccess: index)
        collector.walk(tree)
        return collector.declarations
    }

    /// Walks `tree`, a file of `module`, and returns its API declarations;
    /// only the file's own types cap extensions' members.
    static func collect(_ tree: SourceFileSyntax, module: String) -> [APIDeclaration] {
        let collector = Self(module: module, file: "", typeAccess: TypeAccessIndex(files: [("", tree)]))
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
        let typeCap = typeAccess.memberCap(ofExtended: CanonicalText.render(node.extendedType), in: file)
        scopes.append(scopes[scopes.count - 1].members(ofExtensionWith: node.modifiers, typeCap: typeCap))
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
        scopes.append(scopes[scopes.count - 1].members(ofTypeAt: access, isAtFileScope: scopes.count == 1))
        return .visitChildren
    }

    /// Counts one declaration and returns its effective level.
    @discardableResult
    private func add(_ modifiers: DeclModifierListSyntax, node: Syntax, finality: ClassFinality) -> AccessLevel {
        let scope = scopes[scopes.count - 1]
        let written = AccessLevel.written(in: modifiers)
        let access = scope.level(written: written)
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
