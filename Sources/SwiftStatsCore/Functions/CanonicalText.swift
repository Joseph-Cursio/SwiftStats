//
//  CanonicalText.swift
//  SwiftStatsCore
//
//  Renders syntax as text that ignores comments and formatting, so a key
//  built from it survives reformatting. Tokens are joined with a space only
//  where Swift needs one (between two words) or where it reads better (after
//  `,` and `:`, around `->`, `=` and operators).
//

import SwiftSyntax

/// Formatting-independent text for syntax nodes.
enum CanonicalText {
    /// The node's tokens, joined by the canonical spacing rule.
    static func render(_ node: some SyntaxProtocol) -> String {
        render(tokens: node.tokens(viewMode: .sourceAccurate))
    }

    /// The tokens, joined by the canonical spacing rule. Missing tokens
    /// (inserted by the parser to recover from errors) are skipped.
    static func render(tokens: some Sequence<TokenSyntax>) -> String {
        var text = ""
        var previous: TokenKind?
        for token in tokens where token.presence == .present {
            let kind = token.tokenKind
            if let previous, needsSpace(between: previous, and: kind) {
                text += " "
            }
            text += token.text
            previous = kind
        }
        return text
    }

    /// The node's token texts joined by single spaces: the input to the body
    /// hash, where readability doesn't matter but formatting must not.
    static func tokenStream(_ node: some SyntaxProtocol) -> String {
        node.tokens(viewMode: .sourceAccurate)
            .filter { $0.presence == .present }
            .map(\.text)
            .joined(separator: " ")
    }

    /// Whether the canonical form puts a space between two adjacent tokens.
    private static func needsSpace(between previous: TokenKind, and next: TokenKind) -> Bool {
        if isWord(previous), isWord(next) {
            return true
        }
        if isSpaced(previous) || isSpaced(next) {
            return true
        }
        switch previous {
        case .colon, .comma:
            return true

        case .rightParen:
            // `(T) throws -> U`, `(Int) async`
            return isWord(next)

        default:
            return false
        }
    }

    /// Identifiers, keywords and literals: two in a row need a space.
    private static func isWord(_ kind: TokenKind) -> Bool {
        switch kind {
        case .dollarIdentifier, .floatLiteral, .identifier, .integerLiteral, .keyword, .wildcard:
            return true

        default:
            return false
        }
    }

    /// Tokens written with a space on both sides.
    private static func isSpaced(_ kind: TokenKind) -> Bool {
        switch kind {
        case .arrow, .binaryOperator, .equal:
            return true

        default:
            return false
        }
    }
}
