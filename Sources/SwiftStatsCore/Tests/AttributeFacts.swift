//
//  AttributeFacts.swift
//  SwiftStatsCore
//
//  Attributes as written, including those inside an `#if` in an attribute
//  list (`#if canImport(Testing) @Test #endif`).
//

import SwiftSyntax

/// Reads attribute lists.
enum AttributeFacts {
    /// Every attribute in `list`, in order, those in each `#if` branch included.
    static func attributes(in list: AttributeListSyntax) -> [AttributeSyntax] {
        list.flatMap { element -> [AttributeSyntax] in
            switch element {
            case .attribute(let attribute):
                return [attribute]

            case .ifConfigDecl(let ifConfig):
                return ifConfig.clauses.flatMap { clause -> [AttributeSyntax] in
                    guard case .attributes(let nested) = clause.elements else {
                        return []
                    }
                    return attributes(in: nested)
                }
            }
        }
    }

    /// The Swift Testing `@Test` attribute in `list`, if there is one.
    static func testAttribute(in list: AttributeListSyntax) -> AttributeSyntax? {
        attributes(in: list).first { attribute in
            let name = CanonicalText.render(attribute.attributeName)
            return name == "Test" || name == "Testing.Test"
        }
    }
}
