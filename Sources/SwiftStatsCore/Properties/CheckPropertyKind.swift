//
//  CheckPropertyKind.swift
//  SwiftStatsCore
//
//  What a `@CheckProperty` attribute asks SwiftInferProperties' macro to
//  test (PRD §7.11), read as the macro reads its first argument:
//  `.idempotent`; `.roundTrip(pairedWith: "<name>")`, the name a plain
//  string literal; or `.preservesInvariant(\.<path>)`. The macro rejects
//  anything else with a diagnostic and expands into no test, so it checks
//  nothing. Each kind checks only its own law, so a suggestion is linked
//  to the macro only when its template is that law.
//

import SwiftSyntax

/// The law a `@CheckProperty` attribute's test checks.
enum CheckPropertyKind: Hashable {
    /// `.idempotent`: `f(f(x)) == f(x)` for a unary `f` from a type to
    /// itself.
    case idempotent
    /// `.preservesInvariant(_:)`: the key path holds of `f(x)` whenever it
    /// holds of `x`.
    case preservesInvariant
    /// `.roundTrip(pairedWith:)`: `g(f(x)) == x`, with `g`'s base name.
    case roundTrip(pairedWith: String)

    /// The attribute's name.
    static let attribute = "CheckProperty"
    /// The templates whose law `.idempotent` checks: on a value, or on an
    /// array (`idempotence-lifted`). The macro takes only a unary function
    /// from a type to itself, so no binary or mutating form.
    static let idempotenceTemplates: Set = ["idempotence", "idempotence-lifted"]
    /// The template `.roundTrip` checks.
    static let roundTripTemplate = "round-trip"
    /// The template `.preservesInvariant` checks.
    static let invariantTemplate = "invariant-preservation"

    /// The kind `attribute`'s argument names; nil when the macro would
    /// reject it.
    init?(_ attribute: AttributeSyntax) {
        guard case .argumentList(let arguments) = attribute.arguments, let argument = arguments.first?.expression else {
            return nil
        }
        if let member = argument.as(MemberAccessExprSyntax.self) {
            guard member.declName.baseName.text == "idempotent" else {
                return nil
            }
            self = .idempotent
            return
        }
        guard let call = argument.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        switch member.declName.baseName.text {
        case "roundTrip":
            let paired = call.arguments
                .filter { $0.label?.text == "pairedWith" }
                .compactMap { Self.literal($0.expression) }
                .first
            guard let paired else {
                return nil
            }
            self = .roundTrip(pairedWith: PropertyTestLinks.baseName(paired))

        case "preservesInvariant":
            guard call.arguments.first?.expression.is(KeyPathExprSyntax.self) == true else {
                return nil
            }
            self = .preservesInvariant

        default:
            return nil
        }
    }

    /// The kind of each `@CheckProperty` in `file` the macro accepts, by
    /// the place its marker names: the attribute's first token.
    static func collect(_ file: ParsedFile, context: FileContext) -> [RawFinding.Place: Self] {
        guard file.source.contains(attribute) else {
            return [:]
        }
        var kinds: [RawFinding.Place: Self] = [:]
        for token in file.tree.tokens(viewMode: .sourceAccurate) where token.tokenKind == .atSign {
            guard let node = token.parent?.as(AttributeSyntax.self),
                  CanonicalText.render(node.attributeName) == attribute,
                  let kind = Self(node) else {
                continue
            }
            let position = context.position(context.converter.location(for: node.positionAfterSkippingLeadingTrivia))
            kinds[RawFinding.Place(file: context.file, line: position.line, column: position.column)] = kind
        }
        return kinds
    }

    /// The text of a string literal of one plain segment, as the macro
    /// reads `pairedWith:`; nil for anything else.
    private static func literal(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.segments.count == 1 else {
            return nil
        }
        return literal.segments.first?.as(StringSegmentSyntax.self)?.content.text
    }
}
