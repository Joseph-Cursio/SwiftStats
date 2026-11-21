//
//  TypeAccessIndex.swift
//  SwiftStatsCore
//
//  What caps the members of each type a module declares (PRD §7.5, M5),
//  so an extension's members can be capped by the type they extend, as
//  Swift caps them, whichever file declares it. A type's members are
//  capped by its effective level, worked out with the scope rules
//  (`AccessScope`) through every type or extension it is nested in; a
//  `private` type at file scope caps them at `fileprivate`. An extension
//  names a type by its path as written, generic arguments dropped; the
//  declaration in the extension's own file wins, and a file-scoped type of
//  another file is never the one meant.
//

import SwiftSyntax

/// The member caps of a module's types, by path.
struct TypeAccessIndex {
    /// What a type is declared in.
    private enum Parent {
        /// The file's own scope.
        case file
        /// The type at this path.
        case type(String)
        /// An extension of the type at this path, with the level it writes.
        case extended(String, written: AccessLevel?)

        /// The path of the type it is or extends; nil for the file.
        var path: String? {
            switch self {
            case .file:
                return nil

            case .type(let path), .extended(let path, _):
                return path
            }
        }
    }

    /// One declaration of a type.
    private struct Declaration {
        /// Its file.
        let file: String
        /// The level it writes.
        let written: AccessLevel?
        /// What it is declared in.
        let parent: Parent
    }

    /// Collects one file's type declarations.
    private final class Collector: SyntaxVisitor {
        /// The declarations found, by path.
        private(set) var declarations: [String: [Declaration]] = [:]
        /// The file walked.
        private let file: String
        /// The open types and extensions, outermost first.
        private var parents: [Parent] = []

        /// A collector for `file`.
        init(file: String) {
            self.file = file
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            enter(node.name.text, node.modifiers)
        }

        override func visitPost(_: StructDeclSyntax) {
            parents.removeLast()
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            enter(node.name.text, node.modifiers)
        }

        override func visitPost(_: ClassDeclSyntax) {
            parents.removeLast()
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            enter(node.name.text, node.modifiers)
        }

        override func visitPost(_: EnumDeclSyntax) {
            parents.removeLast()
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            enter(node.name.text, node.modifiers)
        }

        override func visitPost(_: ActorDeclSyntax) {
            parents.removeLast()
        }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            enter(node.name.text, node.modifiers)
        }

        override func visitPost(_: ProtocolDeclSyntax) {
            parents.removeLast()
        }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            let extended = TypeAccessIndex.unspecialized(CanonicalText.render(node.extendedType))
            parents.append(.extended(extended, written: AccessLevel.written(in: node.modifiers)))
            return .visitChildren
        }

        override func visitPost(_: ExtensionDeclSyntax) {
            parents.removeLast()
        }

        /// A top-level statement holds only local types.
        override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
            node.item.is(DeclSyntax.self) ? .visitChildren : .skipChildren
        }

        override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        /// Records a type declared with `modifiers` and opens its scope.
        private func enter(_ name: String, _ modifiers: DeclModifierListSyntax) -> SyntaxVisitorContinueKind {
            let parent = parents.last ?? .file
            let path = parent.path.map { $0 + "." + name } ?? name
            let declaration = Declaration(file: file, written: AccessLevel.written(in: modifiers), parent: parent)
            declarations[path, default: []].append(declaration)
            parents.append(.type(path))
            return .visitChildren
        }

        deinit {
            // Nothing to release: the collector holds only value types.
        }
    }

    /// Each type's declarations, by path.
    private let declarations: [String: [Declaration]]

    /// An index of no types: nothing caps an extension's members.
    init() {
        declarations = [:]
    }

    /// The index of the types declared in `files`, one module's.
    init(files: [(path: String, tree: SourceFileSyntax)]) {
        var found: [String: [Declaration]] = [:]
        for file in files {
            let collector = Collector(file: file.path)
            collector.walk(file.tree)
            found.merge(collector.declarations) { $0 + $1 }
        }
        declarations = found
    }

    /// `path` without generic arguments: `Outer.Inner` for `Outer<T>.Inner<U>`.
    static func unspecialized(_ path: String) -> String {
        var depth = 0
        var result = ""
        for character in path {
            if character == "<" {
                depth += 1
            } else if character == ">" {
                depth -= 1
            } else if depth == 0 {
                result.append(character)
            }
        }
        return result
    }

    /// What caps the members of the type an extension in `file` extends,
    /// written `type`; nil when the module declares no such type.
    func memberCap(ofExtended type: String, in file: String) -> AccessLevel? {
        memberCap(of: Self.unspecialized(type), in: file)
    }

    /// What caps the members of the type at `path`, as `file` means it.
    private func memberCap(of path: String, in file: String) -> AccessLevel? {
        guard let found = declarations[path] else {
            return nil
        }
        let local = found.filter { $0.file == file }
        if local.isEmpty == false {
            return local.map(memberCap(of:)).max()
        }
        // Another file's file-scoped type is invisible here.
        return found.map(memberCap(of:)).filter { $0 > .fileprivate }.max()
    }

    /// What caps the members of `declaration`. A parent's path is a strict
    /// prefix of its own, so this ends.
    private func memberCap(of declaration: Declaration) -> AccessLevel {
        let scope: AccessScope
        switch declaration.parent {
        case .file:
            scope = .file

        case .type(let parent):
            let cap = memberCap(of: parent, in: declaration.file) ?? .open
            scope = AccessScope(defaultLevel: .internal, defaultIsWritten: false, cap: cap)

        case let .extended(type, written):
            scope = AccessScope.file.members(
                ofExtensionWritten: written,
                typeCap: memberCap(of: type, in: declaration.file)
            )
        }
        let level = scope.level(written: declaration.written)
        // A `private` type's members are visible in its enclosing scope:
        // the whole file when it is at file scope.
        if case .file = declaration.parent, level == .private {
            return .fileprivate
        }
        return level
    }
}
