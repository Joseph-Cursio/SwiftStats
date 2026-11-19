//
//  FileContext+Spans.swift
//  SwiftStatsCore
//
//  Source ranges and stripped-line counts, shared by the function and type
//  collectors so both measure the same way (PRD §7.2).
//

import SwiftSyntax

extension FileContext {
    /// Whether `token` belongs to an attribute (`@inlinable`, `@available(…)`):
    /// attributes don't count toward stripped lines (PRD §7.2). The walk stops
    /// at the nearest declaration or statement, which an attribute is below.
    static func isAttributeToken(_ token: TokenSyntax) -> Bool {
        var current = token.parent
        while let node = current {
            if node.is(AttributeSyntax.self) {
                return true
            }
            if node.is(DeclSyntax.self) || node.is(StmtSyntax.self)
                || node.is(MemberBlockItemSyntax.self) || node.is(CodeBlockItemSyntax.self) {
                return false
            }
            current = node.parent
        }
        return false
    }

    /// Lines holding at least one token of `node` at or after `start`,
    /// attribute tokens excluded.
    func lineSet(of node: Syntax, from start: AbsolutePosition) -> Set<Int> {
        var lines = Set<Int>()
        for token in node.tokens(viewMode: .sourceAccurate)
        where token.presence == .present && token.positionAfterSkippingLeadingTrivia >= start
            && Self.isAttributeToken(token) == false {
            let first = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
            let last = converter.location(for: token.endPositionBeforeTrailingTrivia).line
            lines.formUnion(first...max(first, last))
        }
        return lines
    }

    /// The stripped lines of `body` without its own opening and closing
    /// braces (PRD §6.6): what the code inside it occupies, whatever the
    /// layout of the braces.
    func innerLineCount(of body: Syntax) -> Int {
        var tokens = body.tokens(viewMode: .sourceAccurate)
            .filter { $0.presence == .present && Self.isAttributeToken($0) == false }[...]
        if tokens.first?.tokenKind == .leftBrace {
            tokens = tokens.dropFirst()
        }
        if tokens.last?.tokenKind == .rightBrace {
            tokens = tokens.dropLast()
        }
        var lines = Set<Int>()
        for token in tokens {
            let first = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
            let last = converter.location(for: token.endPositionBeforeTrailingTrivia).line
            lines.formUnion(first...max(first, last))
        }
        return lines.count
    }

    /// The inclusive span from `start` to the character before `end`.
    func span(from start: AbsolutePosition, to end: AbsolutePosition) -> SourceSpan {
        let startLocation = converter.location(for: start)
        let lastCharacter = AbsolutePosition(utf8Offset: max(start.utf8Offset, end.utf8Offset - 1))
        let endLocation = converter.location(for: lastCharacter)
        return SourceSpan(start: position(startLocation), end: position(endLocation))
    }

    /// A position as external tools report it, BOM bytes included on line 1.
    func position(_ location: SourceLocation) -> SourcePosition {
        let offset = location.line == 1 ? firstLineColumnOffset : 0
        return SourcePosition(line: location.line, column: location.column + offset)
    }
}
