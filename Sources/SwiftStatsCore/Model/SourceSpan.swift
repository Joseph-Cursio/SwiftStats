//
//  SourceSpan.swift
//  SwiftStatsCore
//
//  The source range a record occupies. Named `SourceSpan` to stay clear of
//  SwiftSyntax's own `SourceRange`.
//

/// An inclusive range of source positions within one file.
public struct SourceSpan: Codable, Hashable, Sendable {
    /// Position of the first character of the declaration (its attributes,
    /// if any), after leading comments and whitespace.
    public let start: SourcePosition
    /// Position of the last character of the declaration, before trailing
    /// comments and whitespace.
    public let end: SourcePosition

    /// Creates a span from its two ends.
    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }

    /// Whether `position` falls inside this span, ends included.
    public func contains(_ position: SourcePosition) -> Bool {
        start <= position && position <= end
    }

    /// Whether `span` falls inside this span, ends included.
    func contains(_ span: Self) -> Bool {
        start <= span.start && span.end <= end
    }
}
