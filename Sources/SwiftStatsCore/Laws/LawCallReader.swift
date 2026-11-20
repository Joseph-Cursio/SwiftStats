//
//  LawCallReader.swift
//  SwiftStatsCore
//
//  Reads a kit protocol check and a suppression marker (PRD §7.11). A
//  check's subject is the `for: X.self` argument, else a `using:`,
//  `overEvery:` or `sampling:` argument written `X.gen()` or `X.gen`;
//  nothing else names it, and a generic parameter names nothing. A subject
//  whose first component is a local type in scope names that local type.
//

import Foundation
import SwiftSyntax

/// Reads `check<P>PropertyLaws` calls and suppression markers.
enum LawCallReader {
    /// Argument labels whose `X.gen()` or `X.gen` names the subject.
    private static let generatorLabels = ["using", "overEvery", "sampling"]
    /// What a suppression marker starts with, after `//`.
    private static let markerPrefix = "// ("
    /// What a suppression marker ends with.
    private static let markerSuffix = " suppressed by user marker)"

    /// The check `node` makes, if it calls `check<P>PropertyLaws` for a
    /// protocol in the kit's table, read in `scope` with `generics` the
    /// generic parameters and `locals` the local types in scope.
    static func call(
        _ node: FunctionCallExprSyntax,
        scope: [String],
        generics: Set<String>,
        locals: Set<String>
    ) -> LawFileFacts.Call? {
        guard let name = calleeName(node.calledExpression),
              let protocolName = KitProtocols.checkedProtocol(ofFunction: name) else {
            return nil
        }
        let written = subject(in: node.arguments)
        let head = written.map { name in name.split(separator: ".").first.map(String.init) ?? name }
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
            namesLocalType: typeName != nil && head.map(locals.contains) == true
        )
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
