//
//  SignatureCensus.swift
//  SwiftStatsCore
//
//  Counts the declarations body inference infers, by signature, over the
//  set SwiftEffectInference itself walks: every `func` with a body outside a
//  closure, and every closure-literal binding outside a function, which it
//  treats as a pseudo-method. A signature held more than once is shared, and
//  strict inference never resolves a call to it (PRD §7.10). A signature
//  held at all is a package function's, and an unqualified or `self.` call
//  to it never takes the name heuristic.
//

import SwiftEffectInference
import SwiftSyntax

/// Counts the inferred declarations of one file by signature.
final class SignatureCensus: SyntaxVisitor {
    /// Declarations seen so far, by signature.
    private(set) var counts: [FunctionSignature: Int] = [:]

    /// Creates a census.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// How many inferred declarations in `trees` hold each signature.
    static func counts(in trees: [SourceFileSyntax]) -> [FunctionSignature: Int] {
        let census = Self()
        for tree in trees {
            census.walk(tree)
        }
        return census.counts
    }

    /// The signature `declaration` registers as a pseudo-method: a single
    /// binding outside any function, initialised with a closure literal
    /// whose signature SwiftEffectInference can derive.
    static func closureBindingSignature(of declaration: VariableDeclSyntax) -> FunctionSignature? {
        guard declaration.bindings.count == 1,
              declaration.bindings.first?.initializer?.value.is(ClosureExprSyntax.self) == true,
              isFunctionLocal(declaration) == false else {
            return nil
        }
        return FunctionSignature.from(declaration: declaration)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.body != nil {
            counts[FunctionSignature.from(declaration: node), default: 0] += 1
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if let signature = Self.closureBindingSignature(of: node) {
            counts[signature, default: 0] += 1
        }
        return .visitChildren
    }

    /// Inference never visits declarations inside a closure.
    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
