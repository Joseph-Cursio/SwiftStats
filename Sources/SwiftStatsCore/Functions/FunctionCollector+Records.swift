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

    /// Whether the modifiers make a declaration `private` or `fileprivate`.
    /// `private(set)` restricts only the setter, so it doesn't count.
    static func isFileScoped(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            modifier.detail == nil
                && (modifier.name.tokenKind == .keyword(.private) || modifier.name.tokenKind == .keyword(.fileprivate))
        }
    }

    /// Whether an accessor block has code, as opposed to a protocol
    /// requirement such as `{ get set }`.
    static func hasBody(_ block: AccessorBlockSyntax) -> Bool {
        switch block.accessors {
        case .getter:
            return true

        case .accessors(let accessors):
            return accessors.contains { $0.body != nil }
        }
    }

    /// The `var`/`let` declaration a binding belongs to.
    static func variable(of binding: PatternBindingSyntax) -> VariableDeclSyntax? {
        binding.parent?.parent?.as(VariableDeclSyntax.self)
    }

    /// The condition under which a clause's body is compiled: its own
    /// condition, after the negation of every earlier clause's.
    static func condition(of clause: IfConfigClauseSyntax) -> String {
        var parts: [String] = []
        if let clauses = clause.parent?.as(IfConfigClauseListSyntax.self) {
            for sibling in clauses {
                if sibling.id == clause.id {
                    break
                }
                if let condition = sibling.condition {
                    parts.append("!(" + CanonicalText.render(condition) + ")")
                }
            }
        }
        if let condition = clause.condition {
            parts.append(CanonicalText.render(condition))
        }
        return parts.joined(separator: " && ")
    }

    /// Conditions joined with `&&`, each parenthesised when there are
    /// several and it contains a space.
    static func conjunction(_ conditions: [String]) -> String {
        guard conditions.count > 1 else {
            return conditions.first ?? ""
        }
        return conditions
            .map { $0.contains(" ") ? "(\($0))" : $0 }
            .joined(separator: " && ")
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
    /// Testing `@Test` or an XCTest `test…` method, otherwise a helper.
    func role(forFunction node: FunctionDeclSyntax) -> CodeRole {
        guard context.isTestTarget else {
            return .production
        }
        let isSwiftTesting = node.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else {
                return false
            }
            let name = CanonicalText.render(attribute.attributeName)
            return name == "Test" || name == "Testing.Test"
        }
        return isSwiftTesting || isXCTestMethod(node) ? .test : .helper
    }

    /// Records the draft under the current scopes and opens its own scope.
    func addRecord(_ draft: RecordDraft) {
        var (key, parentKey) = makeKey(declaration: draft.declaration, isFileScoped: draft.isFileScoped)
        if parentKey != nil {
            // Swift allows local functions of the same name in sibling blocks
            // (`if … { func f() } else { func f() }`); number the repeats.
            let occurrence = nestedKeyCounts[key, default: 0] + 1
            nestedKeyCounts[key] = occurrence
            if occurrence > 1 {
                key += " #\(occurrence)"
            }
        }
        let lines = lineSet(of: draft.node, from: draft.countFrom)
        records.append(FunctionRecord(
            key: key,
            module: context.module,
            kind: draft.kind,
            name: draft.name,
            accessorKind: draft.accessorKind,
            file: context.file,
            range: span(
                from: draft.node.positionAfterSkippingLeadingTrivia,
                to: draft.node.endPositionBeforeTrailingTrivia
            ),
            strippedLines: lines.count,
            bodyHash: BodyHash.of(text: draft.bodyTokens),
            parentKey: parentKey,
            ifConfig: conditions.isEmpty ? nil : Self.conjunction(conditions),
            role: draft.role
        ))
        scopes.append(.record(RecordScope(owner: draft.node.id, key: key, conditionDepth: conditions.count)))
    }

    /// Adds the file's synthetic top-level-code record when the file has
    /// top-level statements (PRD §6.1a). Declarations don't count: global
    /// variable initialisers attach to the file instead.
    func addTopLevelCode(_ file: SourceFileSyntax) {
        // A plain loop, not `filter`: filtering a syntax collection builds a
        // detached copy whose positions no longer match the file.
        var statements: [CodeBlockItemSyntax] = []
        for item in file.statements {
            switch item.item {
            case .expr(let expression):
                // A top-level `#Preview { … }` parses as an expression but is
                // a declaration macro, not code that runs.
                if expression.is(MacroExpansionExprSyntax.self) == false {
                    statements.append(item)
                }

            case .stmt:
                statements.append(item)

            case .decl:
                continue
            }
        }
        guard let first = statements.first, let last = statements.last else {
            return
        }
        var lines = Set<Int>()
        for statement in statements {
            lines.formUnion(lineSet(of: Syntax(statement), from: statement.position))
        }
        let (key, _) = makeKey(declaration: "<top-level code>", isFileScoped: true)
        records.append(FunctionRecord(
            key: key,
            module: context.module,
            kind: .topLevelCode,
            name: "<top-level>",
            accessorKind: nil,
            file: context.file,
            range: span(from: first.positionAfterSkippingLeadingTrivia, to: last.endPositionBeforeTrailingTrivia),
            strippedLines: lines.count,
            bodyHash: BodyHash.of(text: statements.map(CanonicalText.tokenStream).joined(separator: " ")),
            parentKey: nil,
            ifConfig: nil,
            role: nonTestRole
        ))
    }

    /// Assembles a key from the open scopes (PRD §6.1). Inside a record the
    /// record's key is the prefix; otherwise the module is.
    private func makeKey(declaration: String, isFileScoped: Bool) -> (key: String, parentKey: String?) {
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
        return (key, parent?.key)
    }

    /// Whether `node` is an XCTest test method: an instance `func` named
    /// `test…` with no parameters, directly inside an `XCTestCase` subclass
    /// or an extension of one.
    private func isXCTestMethod(_ node: FunctionDeclSyntax) -> Bool {
        guard node.name.text.hasPrefix("test"),
              node.signature.parameterClause.parameters.isEmpty,
              DeclarationRenderer.typeLevelPrefix(node.modifiers).isEmpty,
              case .type(let owner)? = scopes.last else {
            return false
        }
        return context.testCaseClasses.contains(owner.simpleName)
    }

    /// Lines holding at least one token of `node` at or after `start`.
    private func lineSet(of node: Syntax, from start: AbsolutePosition) -> Set<Int> {
        var lines = Set<Int>()
        for token in node.tokens(viewMode: .sourceAccurate)
        where token.presence == .present && token.positionAfterSkippingLeadingTrivia >= start {
            let first = context.converter.location(for: token.positionAfterSkippingLeadingTrivia).line
            let last = context.converter.location(for: token.endPositionBeforeTrailingTrivia).line
            lines.formUnion(first...max(first, last))
        }
        return lines
    }

    /// The inclusive span from `start` to the character before `end`.
    private func span(from start: AbsolutePosition, to end: AbsolutePosition) -> SourceSpan {
        let startLocation = context.converter.location(for: start)
        let lastCharacter = AbsolutePosition(utf8Offset: max(start.utf8Offset, end.utf8Offset - 1))
        let endLocation = context.converter.location(for: lastCharacter)
        return SourceSpan(
            start: SourcePosition(line: startLocation.line, column: startLocation.column),
            end: SourcePosition(line: endLocation.line, column: endLocation.column)
        )
    }
}
