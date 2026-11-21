//
//  SwiftTestingIdentity.swift
//  SwiftStatsCore
//
//  What Swift Testing matches a `--skip` regex against for one test (M5,
//  `TestSkipFilter`), beyond its name and type: where its `@Test`
//  attribute's name starts, which Swift Testing takes as the test's source
//  location (the `Test` after the `@`), and its own tags. Also, for a test
//  target, each type declared `@Suite`, by its path, with its tags.
//
//  Swift Testing matches the ID of each `@Suite` type a test's ID passes
//  through, `<module>.<suite types…>`, skipping every test under one that
//  matches, and a test inherits those types' tags. A type without
//  `@Suite` is a suite Swift Testing synthesises only after filtering, so
//  its ID and traits are never matched. A type's path is the names of the
//  types around it and its own, an extension's written type included
//  (`extension A.B { @Suite struct C {} }` declares `A.B.C`).
//
//  A tag is named as Swift Testing names it: `.slow` and `Tag.slow` are
//  `slow`, `.Speed.slow` is `Speed.slow`.
//

import SwiftSyntax

/// What Swift Testing's `--skip` matches for one test.
struct SwiftTestingIdentity: Equatable, Sendable {
    /// The line of the `@Test` attribute's name.
    let line: Int
    /// The column of the `@Test` attribute's name.
    let column: Int
    /// The tags its `@Test` attribute's traits give it.
    let tags: Set<String>

    /// The identity of `function`, whose nodes' line and column `location`
    /// gives; nil when it has no `@Test` attribute.
    init?(_ function: FunctionDeclSyntax, location: (Syntax) -> (line: Int, column: Int)) {
        guard let test = AttributeFacts.testAttribute(in: function.attributes) else {
            return nil
        }
        let place = location(Syntax(test.attributeName))
        line = place.line
        column = place.column
        tags = Self.tags(in: test)
    }

    /// The path of the type `node` declares and the tags its traits give
    /// it, when it is a struct, class, enum or actor declared `@Suite`;
    /// nil otherwise.
    static func suite(_ node: Syntax) -> (path: [String], tags: Set<String>)? {
        guard let attributed = node.asProtocol((any WithAttributesSyntax).self),
              node.is(StructDeclSyntax.self) || node.is(ClassDeclSyntax.self)
                || node.is(EnumDeclSyntax.self) || node.is(ActorDeclSyntax.self),
              let suite = suiteAttribute(in: attributed.attributes) else {
            return nil
        }
        var path: [String] = []
        var current: Syntax? = node
        while let declaration = current {
            path.insert(contentsOf: components(of: declaration), at: 0)
            current = declaration.parent
        }
        return (path, tags(in: suite))
    }

    /// The names `node` adds to the path of the declarations in it: a
    /// type's name, an extension's written type; none for anything else.
    private static func components(of node: Syntax) -> [String] {
        if let extended = node.as(ExtensionDeclSyntax.self) {
            return CallReferenceBuilder.path(of: extended.extendedType)
        }
        guard node.is(StructDeclSyntax.self) || node.is(ClassDeclSyntax.self)
                || node.is(EnumDeclSyntax.self) || node.is(ActorDeclSyntax.self),
              let named = node.asProtocol((any NamedDeclSyntax).self) else {
            return []
        }
        return [CallSignature.name(of: named.name)]
    }

    /// The `@Suite` attribute in `list`, if there is one.
    private static func suiteAttribute(in list: AttributeListSyntax) -> AttributeSyntax? {
        AttributeFacts.attributes(in: list).first { attribute in
            let name = CanonicalText.render(attribute.attributeName)
            return name == "Suite" || name == "Testing.Suite"
        }
    }

    /// The tags `attribute`'s `.tags(…)` traits name.
    private static func tags(in attribute: AttributeSyntax) -> Set<String> {
        guard case .argumentList(let arguments) = attribute.arguments else {
            return []
        }
        var named = Set<String>()
        for argument in arguments {
            guard let trait = argument.expression.as(FunctionCallExprSyntax.self),
                  let callee = trait.calledExpression.as(MemberAccessExprSyntax.self),
                  callee.declName.baseName.text == "tags" else {
                continue
            }
            named.formUnion(trait.arguments.compactMap { tag(of: $0.expression) })
        }
        return named
    }

    /// The name of the tag `expression` writes, without a leading `Tag` or
    /// `Testing.Tag`; nil when it isn't a chain of names.
    private static func tag(of expression: ExprSyntax) -> String? {
        var components = chain(of: expression)
        if components.first == "Testing" {
            components.removeFirst()
        }
        if components.first == "Tag" {
            components.removeFirst()
        }
        return components.isEmpty ? nil : components.joined(separator: ".")
    }

    /// The names of the chain `expression` is, an implicit member's
    /// included (`.Speed.slow` gives `Speed`, `slow`); empty for any other
    /// expression.
    private static func chain(of expression: ExprSyntax) -> [String] {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return [CallSignature.name(of: reference.baseName)]
        }
        guard let member = expression.as(MemberAccessExprSyntax.self) else {
            return []
        }
        let name = CallSignature.name(of: member.declName.baseName)
        guard let base = member.base else {
            return [name]
        }
        let prefix = chain(of: base)
        return prefix.isEmpty ? [] : prefix + [name]
    }
}
