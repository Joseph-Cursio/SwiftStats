//
//  TypeCollector.swift
//  SwiftStatsCore
//
//  Walks one file and emits a record for every type declaration and
//  extension (PRD §7.2): nested types under their enclosing path, local
//  types (in a function body, accessor or closure) under a fresh path.
//

import SwiftSyntax

/// Collects the type records of one source file.
final class TypeCollector: SyntaxVisitor {
    /// The records found so far, in source order.
    private(set) var records: [TypeRecord] = []

    /// The file being walked.
    private let context: FileContext
    /// Type names on the current path, one list per code context: entering
    /// a body or closure starts a new, empty path.
    private var frames: [[String]] = [[]]
    /// Open `#if` conditions, outermost first.
    private var conditions: [String] = []

    /// Creates a collector for the file described by `context`.
    init(context: FileContext) {
        self.context = context
        super.init(viewMode: .sourceAccurate)
    }

    /// Walks `tree` and returns its type records.
    static func collect(_ tree: SourceFileSyntax, context: FileContext) -> [TypeRecord] {
        let collector = Self(context: context)
        collector.walk(tree)
        return collector.records
    }

    /// Members directly in `members`, `#if` branches flattened.
    private static func memberCount(of members: MemberBlockItemListSyntax) -> Int {
        members.reduce(into: 0) { count, item in
            count += memberCount(of: item.decl)
        }
    }

    /// How many members one declaration in a member list adds.
    private static func memberCount(of decl: DeclSyntax) -> Int {
        if let variable = decl.as(VariableDeclSyntax.self) {
            return variable.bindings.count
        }
        if let enumCase = decl.as(EnumCaseDeclSyntax.self) {
            return enumCase.elements.count
        }
        if let ifConfig = decl.as(IfConfigDeclSyntax.self) {
            return ifConfig.clauses.reduce(into: 0) { count, clause in
                if let nested = clause.elements?.as(MemberBlockItemListSyntax.self) {
                    count += memberCount(of: nested)
                }
            }
        }
        return countsAsOneMember(decl) ? 1 : 0
    }

    /// Whether a declaration is one member: a function, initialiser,
    /// deinitialiser, subscript, typealias, associated type or nested type.
    private static func countsAsOneMember(_ decl: DeclSyntax) -> Bool {
        decl.is(FunctionDeclSyntax.self) || decl.is(InitializerDeclSyntax.self)
            || decl.is(DeinitializerDeclSyntax.self) || decl.is(SubscriptDeclSyntax.self)
            || decl.is(TypeAliasDeclSyntax.self) || decl.is(AssociatedTypeDeclSyntax.self)
            || decl.asProtocol(DeclGroupSyntax.self) != nil
    }

    // MARK: - Types

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, kind: .structType, name: node.name.text)
    }

    override func visitPost(_: StructDeclSyntax) {
        leave()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, kind: .classType, name: node.name.text)
    }

    override func visitPost(_: ClassDeclSyntax) {
        leave()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, kind: .enumType, name: node.name.text)
    }

    override func visitPost(_: EnumDeclSyntax) {
        leave()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, kind: .actor, name: node.name.text)
    }

    override func visitPost(_: ActorDeclSyntax) {
        leave()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, kind: .protocolType, name: node.name.text)
    }

    override func visitPost(_: ProtocolDeclSyntax) {
        leave()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, kind: .extensionDeclaration, name: CanonicalText.render(node.extendedType))
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        leave()
    }

    // MARK: - Code contexts

    override func visit(_: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        frames.append([])
        return .visitChildren
    }

    override func visitPost(_: CodeBlockSyntax) {
        frames.removeLast()
    }

    override func visit(_: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        frames.append([])
        return .visitChildren
    }

    override func visitPost(_: AccessorBlockSyntax) {
        frames.removeLast()
    }

    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        frames.append([])
        return .visitChildren
    }

    override func visitPost(_: ClosureExprSyntax) {
        frames.removeLast()
    }

    // MARK: - Macros

    /// Declarations in a macro's arguments get no records, as in
    /// `FunctionCollector`, so a type in `#Preview { … }` isn't counted.
    override func visit(_: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    // MARK: - #if

    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
        conditions.append(FunctionCollector.condition(of: node))
        return .visitChildren
    }

    override func visitPost(_: IfConfigClauseSyntax) {
        conditions.removeLast()
    }

    // MARK: - Records

    /// Records `node` and puts its name on the path.
    private func enter(_ node: some DeclGroupSyntax, kind: TypeKind, name: String) -> SyntaxVisitorContinueKind {
        let path = (frames.last ?? []) + [name]
        let lines = context.lineSet(of: Syntax(node), from: node.attributes.endPosition)
        records.append(TypeRecord(
            module: context.module,
            kind: kind,
            name: path.joined(separator: "."),
            file: context.file,
            range: context.span(
                from: node.positionAfterSkippingLeadingTrivia,
                to: node.endPositionBeforeTrailingTrivia
            ),
            strippedLines: lines.count,
            memberCount: Self.memberCount(of: node.memberBlock.members),
            isLocal: frames.count > 1,
            ifConfig: conditions.isEmpty ? nil : FunctionCollector.conjunction(conditions)
        ))
        frames[frames.count - 1].append(name)
        return .visitChildren
    }

    /// Takes the innermost name off the path.
    private func leave() {
        frames[frames.count - 1].removeLast()
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
