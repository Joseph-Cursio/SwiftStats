import SwiftSyntax

// Each visitor writes state outside itself, so none is value-shaped.
final class EnumRule: SyntaxVisitor {
    var issues: [String] = []

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        issues.append(node.name.text)
        return .visitChildren
    }
}

final class StructRule: SyntaxVisitor {
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        addIssue(node.name.text)
        return .visitChildren
    }

    func addIssue(_ text: String) {
        print(text)
    }
}

final class ClassRule: SyntaxVisitor {
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        helper(node)
        return .visitChildren
    }

    func helper(_ node: ClassDeclSyntax) {
        print(node)
    }
}

// Value-shaped, but an override has no shape.
final class TokenRule: SyntaxVisitor {
    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}

// Appending to a local array is fine.
func evens(in values: [Int]) -> [Int] {
    var built: [Int] = []
    for value in values where value.isMultiple(of: 2) {
        built.append(value)
    }
    return built
}

struct Foo {}

struct Bar {}

// Value-shaped, with no shape.
func convert(_ value: Foo) -> Bar {
    Bar()
}

class Outline {
    func merged(_ other: Outline) -> Outline {
        other
    }
}

final class Box: Outline {
    override func merged(_ other: Outline) -> Outline {
        self
    }
}
