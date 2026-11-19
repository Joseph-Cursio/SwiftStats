//
//  FunctionCollector+Records.swift
//  SwiftStatsCore
//
//  Key assembly, scope bookkeeping and the per-record measurements (range,
//  stripped lines, body hash, role).
//

import SwiftSyntax

extension FunctionCollector {
    /// The role of a non-`func` record: helper in a test target, production
    /// elsewhere. Only functions can be tests.
    var nonTestRole: CodeRole {
        context.isTestTarget ? .helper : .production
    }

    /// Whether the innermost scope is a record or context.
    var isInsideRecordScope: Bool {
        if case .record? = scopes.last {
            return true
        }
        return false
    }

    /// Opens a key context for a binding's initialiser.
    func pushInitializerContext(for binding: PatternBindingSyntax, owner: SyntaxIdentifier) {
        let variable = Self.variable(of: binding)
        let declaration = DeclarationRenderer.initializerContext(binding, variable: variable)
        let isFileScoped = variable.map { Self.isFileScoped($0.modifiers) } ?? false
        let key = makeKey(declaration: declaration, isFileScoped: isFileScoped).key
        scopes.append(.record(RecordScope(owner: owner, key: key, conditionDepth: conditions.count, isRecord: false)))
    }

    /// Opens a type scope.
    func pushType(name: String, modifiers: DeclModifierListSyntax, owner: SyntaxIdentifier) {
        scopes.append(.type(TypeScope(
            owner: owner,
            pathComponent: name,
            simpleName: name,
            isFileScoped: Self.isFileScoped(modifiers)
        )))
    }

    /// Closes the innermost scope if `owner` opened it.
    func popScope(owner: SyntaxIdentifier) {
        if scopes.last?.owner == owner {
            scopes.removeLast()
        }
    }

    /// The role of a `func`: in a test target, a test if it is a Swift
    /// Testing `@Test` (including one inside an `#if` in its attribute list)
    /// or an XCTest `test…` method, otherwise a helper.
    func role(forFunction node: FunctionDeclSyntax) -> CodeRole {
        guard context.isTestTarget else {
            return .production
        }
        let isSwiftTesting = AttributeFacts.testAttribute(in: node.attributes) != nil
        return isSwiftTesting || isXCTestMethod(node) ? .test : .helper
    }

    /// Records the draft under the current scopes and opens its own scope.
    func addRecord(_ draft: RecordDraft) {
        let assembled = makeKey(declaration: draft.declaration, isFileScoped: draft.isFileScoped)
        var key = assembled.key
        let parentKey = assembled.parentKey
        if assembled.isNested {
            // Swift allows local functions of the same name in sibling blocks
            // (`if … { func f() } else { func f() }`); number the repeats.
            let occurrence = nestedKeyCounts[key, default: 0] + 1
            nestedKeyCounts[key] = occurrence
            if occurrence > 1 {
                key += " #\(occurrence)"
            }
        }
        let lines = context.lineSet(of: draft.node, from: draft.countFrom)
        records.append(FunctionRecord(
            key: key,
            module: context.module,
            kind: draft.kind,
            name: draft.name,
            accessorKind: draft.accessorKind,
            file: context.file,
            range: context.span(
                from: draft.node.positionAfterSkippingLeadingTrivia,
                to: draft.node.endPositionBeforeTrailingTrivia
            ),
            strippedLines: lines.count,
            bodyLines: context.innerLineCount(of: draft.body),
            parameterCount: DeclarationFacts.parameterCount(of: draft.node),
            isDocumented: DeclarationFacts.isDocumented(draft.node),
            isAsync: DeclarationFacts.isAsync(draft.node),
            bodyHash: BodyHash.of(text: draft.bodyTokens),
            parentKey: parentKey,
            ifConfig: conditions.isEmpty ? nil : Self.conjunction(conditions),
            role: draft.role
        ))
        scopes.append(.record(RecordScope(
            owner: draft.node.id,
            key: key,
            conditionDepth: conditions.count,
            isRecord: true
        )))
    }

    /// Adds the file's synthetic top-level-code record when the file has
    /// top-level statements (PRD §6.1a), including those in every branch of a
    /// top-level `#if`. Declarations don't count: global variable initialisers
    /// attach to the file instead.
    func addTopLevelCode(_ file: SourceFileSyntax) {
        var statements: [CodeBlockItemSyntax] = []
        Self.collectStatements(file.statements, into: &statements)
        guard let first = statements.first, let last = statements.last else {
            return
        }
        var lines = Set<Int>()
        for statement in statements {
            lines.formUnion(context.lineSet(of: Syntax(statement), from: statement.position))
        }
        let key = makeKey(declaration: "<top-level code>", isFileScoped: true).key
        topLevelKey = key
        topLevelItems = Set(statements.map(\.id))
        records.append(FunctionRecord(
            key: key,
            module: context.module,
            kind: .topLevelCode,
            name: "<top-level>",
            accessorKind: nil,
            file: context.file,
            range: context.span(
                from: first.positionAfterSkippingLeadingTrivia,
                to: last.endPositionBeforeTrailingTrivia
            ),
            strippedLines: lines.count,
            bodyLines: lines.count,
            parameterCount: nil,
            isDocumented: false,
            isAsync: false,
            bodyHash: BodyHash.of(text: statements.map(CanonicalText.tokenStream).joined(separator: " ")),
            parentKey: nil,
            ifConfig: nil,
            role: nonTestRole
        ))
    }

    /// Assembles a key from the open scopes (PRD §6.1). Inside a record or
    /// context its key is the prefix; otherwise the module is. `parentKey`
    /// is set only when the innermost prefix is a record.
    private func makeKey(declaration: String, isFileScoped: Bool) -> AssembledKey {
        var parent: RecordScope?
        var typeScopes: [TypeScope] = []
        for scope in scopes {
            switch scope {
            case .record(let record):
                parent = record
                typeScopes = []

            case .type(let type):
                typeScopes.append(type)
            }
        }
        var key = parent.map { $0.key + " / " } ?? context.module + "::"
        let path = typeScopes.map(\.pathComponent).joined(separator: ".")
        if path.isEmpty == false {
            key += path + "::"
        }
        key += declaration
        let localConditions = Array(conditions.dropFirst(parent?.conditionDepth ?? 0))
        if localConditions.isEmpty == false {
            key += " #if " + Self.conjunction(localConditions)
        }
        if parent == nil, isFileScoped || typeScopes.contains(where: \.isFileScoped) {
            key += " @ " + context.file
        }
        return AssembledKey(key: key, parentKey: parent?.isRecord == true ? parent?.key : nil, isNested: parent != nil)
    }

    /// Whether `node` is an XCTest test method: an instance `func` named
    /// `test…` with no parameters, directly inside an `XCTestCase` subclass
    /// or an extension of one.
    private func isXCTestMethod(_ node: FunctionDeclSyntax) -> Bool {
        let returnType = node.signature.returnClause.map { CanonicalText.render($0.type) }
        guard node.name.text.hasPrefix("test"),
              node.signature.parameterClause.parameters.isEmpty,
              returnType == nil || returnType == "Void" || returnType == "()",
              DeclarationRenderer.typeLevelPrefix(node.modifiers).isEmpty,
              case .type(let owner)? = scopes.last else {
            return false
        }
        return context.testCaseClasses.contains(owner.simpleName)
    }
}
