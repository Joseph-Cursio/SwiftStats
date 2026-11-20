//
//  EffectFactsBuilder.swift
//  SwiftStatsCore
//
//  Turns one site's SwiftEffectInference answers into its `EffectFacts`
//  (PRD §7.10). The resolved tier comes from the first of: a conflicting
//  declaration, `@EffectUnknown`, a declared tier, a `pure` verdict, a tier
//  inferred from the body, nothing.
//

import SwiftEffectInference
import SwiftSyntax

/// Builds the facts of each site from one run's answers.
struct EffectFactsBuilder {
    /// The declared annotations' four answers for one declaration.
    private struct Declaration {
        /// The declared effect, when the forms agree.
        let effect: Effect?
        /// Whether the attribute and doc comment declare different tiers.
        let conflicting: Bool
        /// Whether it declares `@EffectUnknown`.
        let unknown: Bool
        /// Whether it declares `@ClockDeterministic`.
        let clockDeterministic: Bool

        /// The recorded form.
        var facts: EffectFacts.Declaration {
            EffectFacts.Declaration(
                declared: effect.map(EffectNames.tier(of:)),
                keyParameter: effect.flatMap(EffectNames.keyParameter(of:)),
                unknown: unknown,
                clockDeterministic: clockDeterministic
            )
        }
    }

    /// Reads declared tiers.
    let parser: EffectAnnotationParser
    /// Gives purity verdicts, with the run's construction facts.
    let purity: PurityInferrer
    /// The run's body inference.
    let inference: StrictBodyInference
    /// The explaining pass's tiers.
    let results: [FunctionSignature: BodyInference]
    /// The explaining pass's resolved calls, by enclosing function.
    let calls: [SyntaxIdentifier: [StrictBodyInference.ResolvedCall]]

    /// Whether `function` sits inside a closure, where inference never looks.
    private static func isInsideClosure(_ function: FunctionDeclSyntax) -> Bool {
        var current = function.parent
        while let node = current {
            if node.is(ClosureExprSyntax.self) {
                return true
            }
            current = node.parent
        }
        return false
    }

    /// The resolved tier and its source.
    private static func resolve(
        _ declaration: Declaration?,
        purity: EffectFacts.Purity?,
        inferred: EffectFacts.Inferred?
    ) -> (tier: EffectFacts.Tier?, source: EffectFacts.Source) {
        if declaration?.conflicting == true {
            return (nil, .conflicting)
        }
        if declaration?.unknown == true {
            return (nil, .unknown)
        }
        if let effect = declaration?.effect {
            return (EffectNames.tier(of: effect), .declared)
        }
        if purity == .pure {
            return (.pure, .purity)
        }
        if let inferred {
            return (inferred.tier, .bodyInferred)
        }
        return (nil, .unresolved)
    }

    /// The facts of `site`.
    func facts(for site: EffectSite) -> EffectFacts {
        switch site {
        case .function(let function):
            return facts(for: function)

        case let .getter(variable, block, _):
            return accessorFacts(declaration: declaration(of: variable), block: block)

        case let .subscriptDeclaration(_, block):
            return accessorFacts(declaration: nil, block: block)
        }
    }

    /// The facts of a `func`.
    private func facts(for function: FunctionDeclSyntax) -> EffectFacts {
        let declaration = declaration(
            effect: parser.parseEffect(declaration: function),
            documented: parser.parseEffect(leadingTrivia: EffectAnnotationParser.documentationTrivia(for: function)),
            unknown: parser.declaresUnknownEffect(declaration: function),
            clockDeterministic: parser.isClockDeterministic(declaration: function)
        )
        let signature = FunctionSignature.from(declaration: function)
        let inferenceState: EffectFacts.Inference?
        if Self.isInsideClosure(function) {
            inferenceState = nil
        } else if declaration.effect != nil {
            inferenceState = .annotated
        } else if inference.shared.contains(signature) {
            inferenceState = .ambiguous
        } else if inference.isDeclared(signature) {
            inferenceState = .shadowed
        } else {
            inferenceState = .unique
        }
        var inferred: EffectFacts.Inferred?
        if inferenceState == .unique, let result = results[signature] {
            inferred = EffectFacts.Inferred(
                tier: EffectNames.tier(of: result.effect),
                depth: result.depth,
                anchor: EffectNames.anchor(of: result.anchor),
                via: inference.via(for: result.effect, calls: calls[function.id] ?? [])
            )
        }
        let verdict = EffectNames.purity(of: purity.verdict(for: function))
        let (tier, source) = Self.resolve(declaration, purity: verdict, inferred: inferred)
        let valueShaped = ValueShapeAnalyzer.isValueShaped(function)
        return EffectFacts(
            tier: tier,
            source: source,
            declaration: declaration.facts,
            purity: verdict,
            refutation: purity.refutation(for: function).map(EffectNames.refutation),
            function: EffectFacts.Function(
                inference: inferenceState,
                inferred: inferred,
                valueShaped: valueShaped,
                shape: valueShaped ? FunctionShapeClassifier.shape(of: function) : nil
            )
        )
    }

    /// The facts of a getter (with its property's `declaration`) or of a
    /// subscript (with none): purity is the accessor block's, which a
    /// setter or observer refutes, and there is no body inference.
    private func accessorFacts(declaration: Declaration?, block: AccessorBlockSyntax) -> EffectFacts {
        let refutation = purity.refutation(for: block)
        let verdict: EffectFacts.Purity = refutation == nil ? .pure : .refuted
        let (tier, source) = Self.resolve(declaration, purity: verdict, inferred: nil)
        return EffectFacts(
            tier: tier,
            source: source,
            declaration: declaration?.facts,
            purity: verdict,
            refutation: refutation.map(EffectNames.refutation),
            function: nil
        )
    }

    /// The declared annotations of a property.
    private func declaration(of variable: VariableDeclSyntax) -> Declaration {
        declaration(
            effect: parser.parseEffect(declaration: variable),
            documented: parser.parseEffect(leadingTrivia: EffectAnnotationParser.documentationTrivia(for: variable)),
            unknown: parser.declaresUnknownEffect(declaration: variable),
            clockDeterministic: parser.isClockDeterministic(declaration: variable)
        )
    }

    /// A declaration from its answers: `effect` combines both forms and is
    /// nil when they conflict, `documented` reads the doc comment alone, so
    /// a nil `effect` with a documented tier is a conflict.
    private func declaration(
        effect: Effect?,
        documented: Effect?,
        unknown: Bool,
        clockDeterministic: Bool
    ) -> Declaration {
        Declaration(
            effect: effect,
            conflicting: effect == nil && documented != nil,
            unknown: unknown,
            clockDeterministic: clockDeterministic
        )
    }
}
