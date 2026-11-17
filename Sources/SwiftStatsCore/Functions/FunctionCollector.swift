//
//  FunctionCollector.swift
//  SwiftStatsCore
//
//  Walks one file and emits a record for every declaration PRD §6.1a counts
//  as a function. A stack of type and record scopes, plus a stack of open
//  `#if` conditions, supplies the context each key needs.
//

import SwiftSyntax

/// Collects the function records of one source file.
final class FunctionCollector: SyntaxVisitor {
    /// The records found so far, in source order.
    var records: [FunctionRecord] = []

    /// The file being walked.
    let context: FileContext
    /// Open type and record scopes, outermost first.
    var scopes: [CollectorScope] = []
    /// Open `#if` conditions, outermost first.
    var conditions: [String] = []
    /// How often each nested key has been seen, to number local functions
    /// that share a name in sibling blocks of one function.
    var nestedKeyCounts: [String: Int] = [:]
    /// Types this file declares `private` or `fileprivate`.
    var fileScopedTypes: Set<String> = []
    /// Key of the file's top-level-code record, if it has one.
    var topLevelKey: String?
    /// The top-level statements that record covers.
    var topLevelItems: Set<SyntaxIdentifier> = []

    /// Creates a collector for the file described by `context`.
    init(context: FileContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    /// Walks `tree` and returns its records.
    static func collect(_ tree: SourceFileSyntax, context: FileContext) -> [FunctionRecord] {
        let collector = Self(context: context)
        collector.walk(tree)
        return collector.records
    }

    // MARK: - Files and types

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        fileScopedTypes = FileScopedTypes.paths(in: node)
        addTopLevelCode(node)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, modifiers: node.modifiers, owner: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popScope(owner: node.id)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, modifiers: node.modifiers, owner: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popScope(owner: node.id)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, modifiers: node.modifiers, owner: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popScope(owner: node.id)
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, modifiers: node.modifiers, owner: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popScope(owner: node.id)
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(name: node.name.text, modifiers: node.modifiers, owner: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        popScope(owner: node.id)
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extended = CanonicalText.render(node.extendedType)
        let whereClause = node.genericWhereClause.map { " " + CanonicalText.render($0) } ?? ""
        let simpleName = extended.split(separator: ".").last.map(String.init) ?? extended
        let isFileScoped = Self.isFileScoped(node.modifiers)
            || FileScopedTypes.isFileScoped(extended, in: fileScopedTypes)
        scopes.append(.type(TypeScope(
            owner: node.id,
            pathComponent: extended + whereClause,
            simpleName: simpleName,
            isFileScoped: isFileScoped
        )))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popScope(owner: node.id)
    }

    // MARK: - Contexts for local declarations

    /// A top-level statement: declarations inside it (`do { func f() }`)
    /// belong to the file's top-level-code record.
    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        if let topLevelKey, topLevelItems.contains(node.id) {
            scopes.append(.record(RecordScope(owner: node.id, key: topLevelKey, conditionDepth: 0, isRecord: true)))
        }
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockItemSyntax) {
        popScope(owner: node.id)
    }

    /// A stored property's or global's initialiser outside any record:
    /// declarations in its closures are keyed under the property, so they
    /// can't collide with members or globals of the same name.
    override func visit(_ node: InitializerClauseSyntax) -> SyntaxVisitorContinueKind {
        if let binding = node.parent?.as(PatternBindingSyntax.self), isInsideRecordScope == false {
            pushInitializerContext(for: binding, owner: node.id)
        }
        return .visitChildren
    }

    override func visitPost(_ node: InitializerClauseSyntax) {
        popScope(owner: node.id)
    }

    // MARK: - Macros

    /// Code passed to a freestanding macro is the macro's input, not code
    /// the compiler builds as written, so it gets no records (PRD §6.1a).
    override func visit(_: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    // MARK: - #if

    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
        conditions.append(Self.condition(of: node))
        return .visitChildren
    }

    override func visitPost(_: IfConfigClauseSyntax) {
        conditions.removeLast()
    }

    // MARK: - Functions, initialisers, deinitialisers, subscripts

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else {
            return .skipChildren
        }
        addRecord(RecordDraft(
            kind: .function,
            name: node.name.text,
            accessorKind: nil,
            declaration: DeclarationRenderer.function(node),
            isFileScoped: Self.isFileScoped(node.modifiers),
            node: Syntax(node),
            countFrom: node.attributes.endPosition,
            bodyTokens: CanonicalText.tokenStream(body),
            role: role(forFunction: node)
        ))
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        popScope(owner: node.id)
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else {
            return .skipChildren
        }
        addRecord(RecordDraft(
            kind: .initializer,
            name: "init",
            accessorKind: nil,
            declaration: DeclarationRenderer.initializer(node),
            isFileScoped: Self.isFileScoped(node.modifiers),
            node: Syntax(node),
            countFrom: node.attributes.endPosition,
            bodyTokens: CanonicalText.tokenStream(body),
            role: nonTestRole
        ))
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        popScope(owner: node.id)
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else {
            return .skipChildren
        }
        addRecord(RecordDraft(
            kind: .deinitializer,
            name: "deinit",
            accessorKind: nil,
            declaration: "deinit",
            isFileScoped: false,
            node: Syntax(node),
            countFrom: node.attributes.endPosition,
            bodyTokens: CanonicalText.tokenStream(body),
            role: nonTestRole
        ))
        return .visitChildren
    }

    override func visitPost(_ node: DeinitializerDeclSyntax) {
        popScope(owner: node.id)
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let block = node.accessorBlock, Self.hasBody(block) else {
            return .skipChildren
        }
        addRecord(RecordDraft(
            kind: .subscriptDeclaration,
            name: "subscript",
            accessorKind: nil,
            declaration: DeclarationRenderer.subscriptDeclaration(node),
            isFileScoped: Self.isFileScoped(node.modifiers),
            node: Syntax(node),
            countFrom: node.attributes.endPosition,
            bodyTokens: CanonicalText.tokenStream(block),
            role: nonTestRole
        ))
        return .visitChildren
    }

    override func visitPost(_ node: SubscriptDeclSyntax) {
        popScope(owner: node.id)
    }

    // MARK: - Accessors

    /// The implicit getter of a computed property: `var x: Int { … }`.
    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        guard case .getter(let items) = node.accessors,
              let binding = node.parent?.as(PatternBindingSyntax.self) else {
            return .visitChildren
        }
        let variable = Self.variable(of: binding)
        addRecord(RecordDraft(
            kind: .accessor,
            name: CanonicalText.render(binding.pattern),
            accessorKind: "get",
            declaration: DeclarationRenderer.accessor(
                owner: DeclarationRenderer.property(binding, modifiers: variable?.modifiers),
                kind: "get"
            ),
            isFileScoped: variable.map { Self.isFileScoped($0.modifiers) } ?? false,
            node: Syntax(node),
            countFrom: node.position,
            bodyTokens: CanonicalText.tokenStream(items),
            role: nonTestRole
        ))
        return .visitChildren
    }

    override func visitPost(_ node: AccessorBlockSyntax) {
        popScope(owner: node.id)
    }

    /// An explicit accessor: `get`, `set`, `willSet`, `didSet`, `_modify`, …
    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else {
            return .skipChildren
        }
        let kind = node.accessorSpecifier.text
        let block = node.parent?.parent?.as(AccessorBlockSyntax.self)
        var owner = ""
        var name = "subscript"
        var isFileScoped = false
        if let binding = block?.parent?.as(PatternBindingSyntax.self) {
            let variable = Self.variable(of: binding)
            owner = DeclarationRenderer.property(binding, modifiers: variable?.modifiers)
            name = CanonicalText.render(binding.pattern)
            isFileScoped = variable.map { Self.isFileScoped($0.modifiers) } ?? false
        }
        addRecord(RecordDraft(
            kind: .accessor,
            name: name,
            accessorKind: kind,
            declaration: DeclarationRenderer.accessor(owner: owner, kind: kind),
            isFileScoped: isFileScoped,
            node: Syntax(node),
            countFrom: node.attributes.endPosition,
            bodyTokens: CanonicalText.tokenStream(body),
            role: nonTestRole
        ))
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        popScope(owner: node.id)
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
