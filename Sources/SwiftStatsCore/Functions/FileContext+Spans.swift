//
//  FileContext+Spans.swift
//  SwiftStatsCore
//
//  Source ranges and stripped-line counts, shared by the function and type
//  collectors so both measure the same way (PRD §7.2).
//

import SwiftSyntax

extension FileContext {
    /// Lines holding at least one token of `node` at or after `start`.
    func lineSet(of node: Syntax, from start: AbsolutePosition) -> Set<Int> {
        var lines = Set<Int>()
        for token in node.tokens(viewMode: .sourceAccurate)
        where token.presence == .present && token.positionAfterSkippingLeadingTrivia >= start {
            let first = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
            let last = converter.location(for: token.endPositionBeforeTrailingTrivia).line
            lines.formUnion(first...max(first, last))
        }
        return lines
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
