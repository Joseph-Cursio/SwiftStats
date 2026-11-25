//
//  ExportedImports.swift
//  SwiftStatsCore
//
//  The modules a file re-exports (M7, design §5.2, review C14): the first
//  path component of each `import` declaration carrying `@_exported`, at
//  the top level or in any clause of a top-level `#if`, active or not,
//  backticks dropped. A library product's clients see a re-exported
//  package target's public declarations through the product's module, so
//  outskirts retains them as it retains the product's own.
//

import SwiftSyntax

/// Finds the modules one file re-exports.
enum ExportedImports {
    /// The attribute that re-exports an import.
    private static let attribute = "_exported"

    /// The modules `tree` re-exports.
    static func modules(in tree: SourceFileSyntax) -> Set<String> {
        modules(in: tree.statements)
    }

    /// The modules the import declarations among `items`, and in the
    /// clauses of the `#if` blocks among them, re-export.
    private static func modules(in items: CodeBlockItemListSyntax) -> Set<String> {
        var found: Set<String> = []
        for item in items {
            if let declaration = item.item.as(ImportDeclSyntax.self) {
                if isExported(declaration), let module = declaration.path.first?.name.text {
                    found.insert(module.filter { $0 != "`" })
                }
            } else if let block = item.item.as(IfConfigDeclSyntax.self) {
                for clause in block.clauses {
                    if case .statements(let statements) = clause.elements {
                        found.formUnion(modules(in: statements))
                    }
                }
            }
        }
        return found
    }

    /// Whether `declaration` carries `@_exported`.
    private static func isExported(_ declaration: ImportDeclSyntax) -> Bool {
        declaration.attributes.contains { element in
            guard case .attribute(let attribute) = element else {
                return false
            }
            return attribute.attributeName.trimmedDescription == Self.attribute
        }
    }
}
