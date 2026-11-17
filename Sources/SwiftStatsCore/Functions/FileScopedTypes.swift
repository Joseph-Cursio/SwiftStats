//
//  FileScopedTypes.swift
//  SwiftStatsCore
//
//  Finds the types a file declares `private` or `fileprivate`, directly or
//  by nesting inside one. An extension of such a type, even one written
//  without a modifier, can only be seen in this file, so its members' keys
//  need the file too: two files may each declare their own `private struct
//  Book` and extend it identically.
//

import SwiftSyntax

/// Collects the dotted paths of file-scoped types in one file.
final class FileScopedTypes: SyntaxVisitor {
    /// Paths of file-scoped types, such as `Book` or `Outer.Inner`.
    private var paths: Set<String> = []
    /// Enclosing type names and whether each is file-scoped.
    private var stack: [(name: String, isFileScoped: Bool)] = []

    /// Creates a visitor.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// The dotted paths of file-scoped types declared in `tree`.
    static func paths(in tree: SourceFileSyntax) -> Set<String> {
        let visitor = Self()
        visitor.walk(tree)
        return visitor.paths
    }

    /// Whether an extension of `extendedType` (as written) extends a
    /// file-scoped type: the type itself or any type it is nested in.
    static func isFileScoped(_ extendedType: String, in paths: Set<String>) -> Bool {
        var prefix = ""
        for component in extendedType.split(separator: ".") {
            prefix = prefix.isEmpty ? String(component) : prefix + "." + component
            if paths.contains(prefix) {
                return true
            }
        }
        return false
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) {
        stack.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) {
        stack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) {
        stack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visitPost(_: ActorDeclSyntax) {
        stack.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visitPost(_: ProtocolDeclSyntax) {
        stack.removeLast()
    }

    /// An extension's nested types live under the extended type's path. A
    /// `private extension` makes them file-scoped, but not the extended type.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        stack.append((CanonicalText.render(node.extendedType), FunctionCollector.isFileScoped(node.modifiers)))
        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        stack.removeLast()
    }

    /// Local types inside function bodies are already scoped by their
    /// parent record's key.
    override func visit(_: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    /// Records a type and opens its scope.
    private func push(_ name: String, _ modifiers: DeclModifierListSyntax) {
        let isFileScoped = FunctionCollector.isFileScoped(modifiers) || stack.last?.isFileScoped == true
        stack.append((name, isFileScoped))
        if isFileScoped {
            paths.insert(stack.map(\.name).joined(separator: "."))
        }
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
