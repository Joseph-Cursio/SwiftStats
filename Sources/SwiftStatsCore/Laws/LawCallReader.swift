//
//  LawCallReader.swift
//  SwiftStatsCore
//
//  Reads a kit protocol check and a suppression marker (PRD §7.11). A
//  check's subject is the `for: X.self` argument, else a `using:`,
//  `overEvery:` or `sampling:` argument written `X.gen()` or `X.gen`;
//  nothing else names it, and a generic parameter names nothing. A subject
//  whose first component is a typealias local to the call is read through
//  it; one whose first component is then a local type in scope names that
//  local type.
//

import Foundation
import SwiftSyntax

/// Reads `check<P>PropertyLaws` calls and suppression markers.
enum LawCallReader {
    /// The types and typealiases a function body, closure or local type
    /// declares directly.
    struct LocalNames {
        /// The types.
        var types: Set<String> = []
        /// The typealiases, each with the type it names: a dotted path
        /// with generic arguments stripped, else its value as written.
        var aliases: [String: String] = [:]

        /// Adds `other`'s names; an alias already here is kept.
        mutating func formUnion(_ other: Self) {
            types.formUnion(other.types)
            aliases.merge(other.aliases) { kept, _ in kept }
        }
    }

    /// Argument labels whose `X.gen()` or `X.gen` names the subject.
    private static let generatorLabels = ["using", "overEvery", "sampling"]
    /// How many local typealiases a subject is read through before it
    /// counts as unnamed, which stops a cycle.
    private static let maximumAliasHops = 8
    /// What a suppression marker starts with, after `//`.
    private static let markerPrefix = "// ("
    /// What a suppression marker ends with.
    private static let markerSuffix = " suppressed by user marker)"

    /// The check `node` makes, if it calls `check<P>PropertyLaws` for a
    /// protocol in the kit's table, read in `scope` with `generics` the
    /// generic parameters and `locals` the local names in scope, outermost
    /// first.
    static func call(
        _ node: FunctionCallExprSyntax,
        scope: [String],
        generics: Set<String>,
        locals: [LocalNames]
    ) -> LawFileFacts.Call? {
        guard let name = calleeName(node.calledExpression),
              let protocolName = KitProtocols.checkedProtocol(ofFunction: name) else {
            return nil
        }
        let (written, isLocal) = subject(in: node.arguments).map { read($0, locals: locals) } ?? (nil, false)
        let head = written.map(Self.head)
        let typeName = head.map { $0 == "Self" || generics.contains($0) } == true ? nil : written
        let ownOnly = node.arguments.contains { argument in
            argument.label?.text == "laws"
                && argument.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "ownOnly"
        }
        return LawFileFacts.Call(
            protocolName: protocolName,
            typeName: typeName,
            scope: scope,
            ownOnly: ownOnly,
            namesLocalType: typeName != nil && isLocal
        )
    }

    /// `written` read through the local typealiases in `locals`, innermost
    /// first, and whether its first component is then a local type; nil
    /// when an alias names no plain type or the aliases loop.
    private static func read(_ written: String, locals: [LocalNames]) -> (String?, Bool) {
        var name = written
        var frame = locals.count - 1
        var hops = 0
        while frame >= 0 {
            let first = head(name)
            if locals[frame].types.contains(first) {
                return (name, true)
            }
            guard let value = locals[frame].aliases[first] else {
                frame -= 1
                continue
            }
            hops += 1
            guard hops <= maximumAliasHops, let target = typeName(value) else {
                return (nil, false)
            }
            name = target + name.dropFirst(first.count)
        }
        return (name, false)
    }

    /// The first component of a dotted type name.
    private static func head(_ name: String) -> String {
        name.split(separator: ".").first.map(String.init) ?? name
    }

    /// The suppression markers in the comments of `tree`.
    static func markers(in tree: SourceFileSyntax) -> [LawFileFacts.Marker] {
        tree.tokens(viewMode: .sourceAccurate).flatMap { token in
            (Array(token.leadingTrivia) + Array(token.trailingTrivia)).compactMap { piece -> LawFileFacts.Marker? in
                guard case .lineComment(let text) = piece else {
                    return nil
                }
                return marker(text)
            }
        }
    }

    /// The marker a line comment holds, if it is one.
    static func marker(_ comment: String) -> LawFileFacts.Marker? {
        let text = comment.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix(markerPrefix), text.hasSuffix(markerSuffix) else {
            return nil
        }
        let body = text.dropFirst(markerPrefix.count).dropLast(markerSuffix.count)
        guard let separator = body.range(of: " for "),
              let protocolName = KitProtocols.checkedProtocol(ofFunction: String(body[..<separator.lowerBound])),
              let typeName = typeName(String(body[separator.upperBound...])) else {
            return nil
        }
        return LawFileFacts.Marker(protocolName: protocolName, typeName: typeName)
    }

    /// `text` as a type name: whitespace and generic arguments removed,
    /// nil unless what is left is a dotted path of identifiers.
    static func typeName(_ text: String) -> String? {
        var name = ""
        var depth = 0
        for character in text where character.isWhitespace == false {
            if character == "<" {
                depth += 1
            } else if character == ">" {
                depth -= 1
            } else if depth == 0 {
                name.append(character)
            }
        }
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        let isPath = depth == 0 && components.allSatisfy { component in
            guard let first = component.first, first.isLetter || first == "_" else {
                return false
            }
            return component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
        return isPath ? name : nil
    }

    /// The function a call names: a bare name or `PropertyLawKit.<name>`.
    private static func calleeName(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        guard let access = expression.as(MemberAccessExprSyntax.self),
              access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "PropertyLawKit" else {
            return nil
        }
        return access.declName.baseName.text
    }

    /// The subject the arguments name, as written.
    private static func subject(in arguments: LabeledExprListSyntax) -> String? {
        if let forArgument = arguments.first(where: { $0.label?.text == "for" }),
           let access = forArgument.expression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "self",
           let base = access.base,
           let name = typeName(base.trimmedDescription) {
            return name
        }
        for label in generatorLabels {
            guard let argument = arguments.first(where: { $0.label?.text == label }),
                  let base = generatorBase(argument.expression) else {
                continue
            }
            return typeName(base.trimmedDescription)
        }
        return nil
    }

    /// `X` when `expression` is `X.gen()` or `X.gen`.
    private static func generatorBase(_ expression: ExprSyntax) -> ExprSyntax? {
        var reference = expression
        if let call = expression.as(FunctionCallExprSyntax.self) {
            guard call.arguments.isEmpty, call.trailingClosure == nil else {
                return nil
            }
            reference = call.calledExpression
        }
        guard let access = reference.as(MemberAccessExprSyntax.self), access.declName.baseName.text == "gen" else {
            return nil
        }
        return access.base
    }
}
