//
//  FunctionCollector+Syntax.swift
//  SwiftStatsCore
//
//  Questions the collector asks of syntax nodes, independent of its state.
//

import SwiftSyntax

extension FunctionCollector {
    /// Accessors that set a property or subscript, or observe its
    /// setting, and so take a `private(set)`-style level.
    static let settingAccessors: Set<String> = [
        "set", "_modify", "modify", "willSet", "didSet", "unsafeMutableAddress", "init"
    ]

    /// Walks `tree` and returns its records.
    static func collect(_ tree: SourceFileSyntax, context: FileContext) -> [FunctionRecord] {
        walked(tree, context: context).records
    }

    /// A collector that has walked `tree`, for its records and selectors.
    static func walked(_ tree: SourceFileSyntax, context: FileContext) -> FunctionCollector {
        let collector = Self(context: context)
        collector.walk(tree)
        return collector
    }

    /// Whether the modifiers make a declaration `private` or `fileprivate`.
    /// `private(set)` restricts only the setter, so it doesn't count.
    static func isFileScoped(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            modifier.detail == nil
                && (modifier.name.tokenKind == .keyword(.private) || modifier.name.tokenKind == .keyword(.fileprivate))
        }
    }

    /// The effective level, under `scope`'s rules, of the declaration of
    /// the record `node` opens: a function, initialiser or subscript by its
    /// own modifiers, an accessor by its property's or subscript's (a
    /// setting one capped by a `private(set)`-style modifier), a
    /// deinitialiser by the scope's default.
    static func accessLevel(of node: Syntax, in scope: AccessScope) -> AccessLevel {
        if let function = node.as(FunctionDeclSyntax.self) {
            return scope.level(of: function.modifiers)
        }
        if let initializer = node.as(InitializerDeclSyntax.self) {
            return scope.level(of: initializer.modifiers)
        }
        if let subscriptDecl = node.as(SubscriptDeclSyntax.self) {
            return scope.level(of: subscriptDecl.modifiers)
        }
        if let block = node.as(AccessorBlockSyntax.self) {
            let binding = block.parent?.as(PatternBindingSyntax.self)
            return scope.level(of: binding.flatMap(variable(of:))?.modifiers ?? DeclModifierListSyntax([]))
        }
        guard let accessor = node.as(AccessorDeclSyntax.self) else {
            return scope.level(written: nil)
        }
        let owner = accessor.parent?.parent?.parent
        let modifiers = owner?.as(SubscriptDeclSyntax.self)?.modifiers
            ?? owner?.as(PatternBindingSyntax.self).flatMap(variable(of:))?.modifiers
            ?? DeclModifierListSyntax([])
        let level = scope.level(of: modifiers)
        guard settingAccessors.contains(accessor.accessorSpecifier.text),
              let setter = AccessLevel.writtenForSetter(in: modifiers) else {
            return level
        }
        return min(level, setter)
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

    /// Whether `node` is an explicit accessor of a subscript.
    static func isSubscriptAccessor(_ node: Syntax) -> Bool {
        node.as(AccessorDeclSyntax.self)?.parent?.parent?.parent?.is(SubscriptDeclSyntax.self) == true
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
            let own = CanonicalText.render(condition)
            // `!(A) && B || C` would read as `(!A && B) || C`.
            parts.append(parts.isEmpty || own.contains(" ") == false ? own : "(\(own))")
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

    /// The lines a file's top-level statements span, each from its first
    /// token to its last: where its top-level-code record runs, since the
    /// declarations between statements don't belong to it (PRD §6.1a).
    static func topLevelLines(in file: SourceFileSyntax, converter: SourceLocationConverter) -> Set<Int> {
        var statements: [CodeBlockItemSyntax] = []
        collectStatements(file.statements, into: &statements)
        return statements.reduce(into: Set<Int>()) { lines, statement in
            let first = converter.location(for: statement.positionAfterSkippingLeadingTrivia).line
            let last = converter.location(for: statement.endPositionBeforeTrailingTrivia).line
            lines.formUnion(first...last)
        }
    }

    /// Top-level statements of `items`, descending into `#if` branches. A
    /// plain loop, not `filter`: filtering a syntax collection builds a
    /// detached copy whose positions no longer match the file.
    static func collectStatements(
        _ items: CodeBlockItemListSyntax,
        into statements: inout [CodeBlockItemSyntax]
    ) {
        for item in items {
            switch item.item {
            case .expr(let expression):
                // A top-level `#Preview { … }` parses as an expression but is
                // a declaration macro, not code that runs.
                if expression.is(MacroExpansionExprSyntax.self) == false {
                    statements.append(item)
                }

            case .stmt:
                statements.append(item)

            case .decl(let declaration):
                guard let ifConfig = declaration.as(IfConfigDeclSyntax.self) else {
                    continue
                }
                for clause in ifConfig.clauses {
                    if case .statements(let nested)? = clause.elements {
                        collectStatements(nested, into: &statements)
                    }
                }
            }
        }
    }
}
