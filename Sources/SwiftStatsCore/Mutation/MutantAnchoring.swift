//
//  MutantAnchoring.swift
//  SwiftStatsCore
//
//  A mutant's anchor in a scanned file (M6, design §3). SwiftMutator gives
//  a point, no end, and which point depends on the operator: most mutants
//  start at a token; the relational swaps, `&&`/`||` and the boundary
//  mutants start at a binary operator's leading trivia (the end of the
//  previous line when the operator starts a line); RemoveSideEffects,
//  SwapTernary's first link and the `false` constants point one past a
//  statement or operand after its trailing trivia, past a trailing comment
//  when there is one. So the anchor is a position inside a token of the
//  file's syntax tree: the point itself when it is on a token's text (a
//  token's start; SwiftMutator gives nothing inside one); else, in trivia,
//  the start of the first token at or after it for those swaps, and the
//  last character of the last token ending at or before it for every other
//  operator, either falling back to the other when there is none. The tree
//  counts no byte order mark, as SwiftMutator doesn't; the anchor is given
//  as records count positions, the mark's 3 bytes counted on line 1. A
//  point the file doesn't hold has no anchor.
//

import SwiftSyntax

/// Anchors the mutants of one scanned file.
struct MutantAnchoring {
    /// The operators whose point may lie in the leading trivia of the
    /// binary operator they change, which their anchor is.
    private static let operatorSwaps: Set<String> = [
        "ChangeLogicalConnector", "RelationalBoundary", "RelationalOperatorReplacement"
    ]
    /// The relational replacements that make a constant, whose `false` is
    /// pointed at past the comparison rather than at an operator.
    private static let constants: Set<String> = ["true", "false"]
    /// The high bits of a UTF-8 continuation byte.
    private static let continuationBits: UInt8 = 0b1100_0000
    /// A UTF-8 continuation byte's high bits, `10`.
    private static let continuationMark: UInt8 = 0b1000_0000

    /// The file's tree.
    private let tree: SourceFileSyntax
    /// Converts between the tree's positions and lines and columns.
    private let converter: SourceLocationConverter
    /// The file's text, as UTF-8.
    private let bytes: [UInt8]
    /// What line-1 columns add for a byte order mark.
    private let firstLineOffset: Int

    /// An anchoring of `file`'s mutants.
    init(_ file: ParsedFile) {
        tree = file.tree
        converter = SourceLocationConverter(fileName: file.path, tree: file.tree)
        bytes = Array(file.source.utf8)
        firstLineOffset = file.hasByteOrderMark ? ParsedFile.byteOrderMarkLength : 0
    }

    /// Whether the anchor of a mutant of `operatorID` making `after` is the
    /// operator its point leads up to.
    static func anchorsForward(operatorID: String, after: String) -> Bool {
        guard operatorSwaps.contains(operatorID) else {
            return false
        }
        return operatorID != "RelationalOperatorReplacement" || constants.contains(after) == false
    }

    /// `token` when it spells something; for the end-of-file token, which
    /// spells nothing, the last token before it; nil when there is none.
    /// So the last token ending at or before a point at the file's end.
    private static func spelled(_ token: TokenSyntax?) -> TokenSyntax? {
        guard let token, token.tokenKind == .endOfFile else {
            return token
        }
        return token.previousToken(viewMode: .sourceAccurate)
    }

    /// The anchor of a mutant of `operatorID` making `after` at SwiftMutator's
    /// `line` and `column` (a byte order mark not counted), as records count
    /// positions; nil when the file holds no such point.
    func anchor(line: Int, column: Int, operatorID: String, after: String) -> SourcePosition? {
        let point = converter.position(ofLine: line, column: column)
        let back = converter.location(for: point)
        guard back.line == line, back.column == column else {
            return nil
        }
        let token = point < tree.endPosition ? tree.token(at: point) : nil
        if let token, token.positionAfterSkippingLeadingTrivia <= point,
           point < token.endPositionBeforeTrailingTrivia {
            return position(of: point)
        }
        let next: TokenSyntax?
        let previous: TokenSyntax?
        if let token {
            if point < token.positionAfterSkippingLeadingTrivia {
                next = token
                previous = token.previousToken(viewMode: .sourceAccurate)
            } else {
                next = token.nextToken(viewMode: .sourceAccurate)
                previous = token
            }
        } else {
            next = nil
            previous = tree.lastToken(viewMode: .sourceAccurate)
        }
        let start = next.flatMap { $0.tokenKind == .endOfFile ? nil : $0.positionAfterSkippingLeadingTrivia }
        let last = Self.spelled(previous).map(lastCharacter(of:))
        let anchor = Self.anchorsForward(operatorID: operatorID, after: after) ? start ?? last : last ?? start
        return anchor.map(position(of:))
    }

    /// Where the last character of `token`'s text starts.
    private func lastCharacter(of token: TokenSyntax) -> AbsolutePosition {
        let start = token.positionAfterSkippingLeadingTrivia.utf8Offset
        var offset = token.endPositionBeforeTrailingTrivia.utf8Offset - 1
        while offset > start, offset < bytes.count, bytes[offset] & Self.continuationBits == Self.continuationMark {
            offset -= 1
        }
        return AbsolutePosition(utf8Offset: max(start, offset))
    }

    /// `position` of the tree as records count positions.
    private func position(of position: AbsolutePosition) -> SourcePosition {
        let location = converter.location(for: position)
        return SourcePosition(line: location.line, column: location.column + (location.line == 1 ? firstLineOffset : 0))
    }
}
