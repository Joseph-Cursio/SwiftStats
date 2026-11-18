//
//  SwiftLintReportTokens.swift
//  SwiftStatsCoreTests
//
//  Where SwiftLint reports each `func` and `init` with a body: the `func`
//  keyword (or a leading `static` / `class`), or the `init` keyword.
//

import SwiftSyntax

/// Maps each scored declaration's start to the token SwiftLint reports at.
final class SwiftLintReportTokens: SyntaxVisitor {
    /// Report positions keyed by "line:column" of the declaration's start.
    private(set) var positions: [String: String] = [:]

    /// Converts positions to lines and columns.
    private let converter: SourceLocationConverter

    /// Creates a visitor for a file.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// The report positions in `tree`, as "line:column", keyed by "line:column" of each start.
    static func positions(in tree: SourceFileSyntax, file: String) -> [String: String] {
        let visitor = Self(converter: SourceLocationConverter(fileName: file, tree: tree))
        visitor.walk(tree)
        return visitor.positions
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        guard node.body != nil else {
            return
        }
        let modifier = node.modifiers.first { modifier in
            modifier.name.tokenKind == .keyword(.static) || modifier.name.tokenKind == .keyword(.class)
        }
        add(start: node.positionAfterSkippingLeadingTrivia, token: (modifier?.name ?? node.funcKeyword))
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        guard node.body != nil else {
            return
        }
        add(start: node.positionAfterSkippingLeadingTrivia, token: node.initKeyword)
    }

    /// Records one declaration.
    private func add(start: AbsolutePosition, token: TokenSyntax) {
        let begin = converter.location(for: start)
        let report = converter.location(for: token.positionAfterSkippingLeadingTrivia)
        positions["\(begin.line):\(begin.column)"] = "\(report.line):\(report.column)"
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
