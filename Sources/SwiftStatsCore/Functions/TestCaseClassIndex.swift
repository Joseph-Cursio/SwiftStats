//
//  TestCaseClassIndex.swift
//  SwiftStatsCore
//
//  Finds the classes in a test target that descend from `XCTestCase`, even
//  through an intermediate base class declared in another file of the same
//  target, so their `test…` methods are recognised as tests.
//

import SwiftSyntax

/// Finds `XCTestCase` subclasses across one target's files.
final class TestCaseClassIndex: SyntaxVisitor {
    /// Each class's first inherited type, by bare class name.
    private var superclassOf: [String: String] = [:]

    /// Creates an empty index.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Names of classes in `trees` that descend from `XCTestCase`.
    static func testCaseClasses(in trees: [SourceFileSyntax]) -> Set<String> {
        let index = Self()
        for tree in trees {
            index.walk(tree)
        }
        return index.descendants(of: "XCTestCase")
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if let first = node.inheritanceClause?.inheritedTypes.first {
            let rendered = CanonicalText.render(first.type)
            superclassOf[node.name.text] = rendered.split(separator: ".").last.map(String.init) ?? rendered
        }
        return .visitChildren
    }

    /// Classes whose superclass chain reaches `root`.
    private func descendants(of root: String) -> Set<String> {
        var result = Set<String>()
        for name in superclassOf.keys {
            var current = superclassOf[name]
            var visited: Set<String> = [name]
            while let next = current, visited.contains(next) == false {
                if next == root {
                    result.insert(name)
                    break
                }
                visited.insert(next)
                current = superclassOf[next]
            }
        }
        return result
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
