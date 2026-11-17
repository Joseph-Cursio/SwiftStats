//
//  SitrepFileVisitor.swift
//  SwiftStatsCore
//
//  Reproduces what Sitrep's `FileVisitor` sees in one file. Sitrep nests
//  types only under classes, enums, extensions, protocols, structs and
//  functions, so a type is "top-level" when none of those encloses it: a type
//  inside an actor, an initialiser body or a closure still counts, and a type
//  nested in a struct doesn't. Matching that exactly is what lets `sitrep -f
//  json` act as an oracle (PRD §7.1).
//

import Foundation
import SwiftSyntax

/// Collects the Sitrep facts of one file.
final class SitrepFileVisitor: SyntaxVisitor {
    /// Top-level types, in source order.
    private var types: [SitrepTypeFact] = []
    /// Import paths, in source order.
    private var imports: [String] = []
    /// How many Sitrep "nodes" (types and functions) enclose the walk.
    private var depth = 0

    /// Creates a visitor.
    init() {
        super.init(viewMode: .fixedUp)
    }

    /// The Sitrep facts of `tree`, whose source text is `source`.
    static func facts(for tree: SourceFileSyntax, source: String, path: String) -> SitrepFileFacts {
        let visitor = Self()
        visitor.walk(tree)
        return SitrepFileFacts(
            path: path,
            newlineCount: SitrepLines.newlineCount(source),
            nonEmptyLineCount: SitrepLines.nonEmptyLineCount(source),
            types: visitor.types,
            imports: visitor.imports
        )
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record("class", name: node.name.text, inheritance: node.inheritanceClause, node: node)
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) {
        depth -= 1
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record("enum", name: node.name.text, inheritance: node.inheritanceClause, node: node)
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) {
        depth -= 1
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        record("extension", name: node.extendedType.description, inheritance: node.inheritanceClause, node: node)
        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        depth -= 1
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record("protocol", name: node.name.text, inheritance: node.inheritanceClause, node: node)
        return .visitChildren
    }

    override func visitPost(_: ProtocolDeclSyntax) {
        depth -= 1
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record("struct", name: node.name.text, inheritance: node.inheritanceClause, node: node)
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) {
        depth -= 1
    }

    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        depth += 1
        return .visitChildren
    }

    override func visitPost(_: FunctionDeclSyntax) {
        depth -= 1
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        imports.append(node.path.description)
        return .visitChildren
    }

    /// Records a type if Sitrep would see it as top-level, then descends.
    private func record(
        _ kind: String,
        name: String,
        inheritance: InheritanceClauseSyntax?,
        node: some SyntaxProtocol
    ) {
        if depth == 0 {
            let inherited = inheritance?.inheritedTypes.map { entry in
                entry.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? []
            types.append(SitrepTypeFact(
                kind: kind,
                name: name.trimmingCharacters(in: .whitespaces),
                inheritance: inherited,
                lineCount: max(SitrepLines.nonEmptyLineCount(node.description), 1)
            ))
        }
        depth += 1
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
