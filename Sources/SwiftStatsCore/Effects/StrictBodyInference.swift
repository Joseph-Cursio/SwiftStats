//
//  StrictBodyInference.swift
//  SwiftStatsCore
//
//  Body inference with strict callee resolution (PRD §7.10). SwiftEffect-
//  Inference keys inferred tiers by signature and merges every declaration
//  that shares one, which spreads a tier to callers that never call the
//  declaration it came from. Here a call to a shared signature that no
//  annotation declares resolves to nothing; everything else (the lattice,
//  the walk, the escaping-closure rule, the heuristics) is SwiftEffect-
//  Inference's own. Each pass reads only the previous pass's map (Jacobi
//  iteration), so file order can't change the result, and the loop has no
//  clock: it stops when a pass changes no tier, or fails the collector
//  after `maxPasses`.
//

import SwiftEffectInference
import SwiftSyntax

/// Strict body inference over one universe of files.
struct StrictBodyInference {
    /// How a call was resolved.
    enum Resolution {
        /// By a name or framework heuristic.
        case heuristic
        /// By the declared or inferred tier of the callee with this signature.
        case callee(FunctionSignature)
    }

    /// One resolved call in the explaining pass.
    struct ResolvedCall {
        /// The call.
        let call: FunctionCallExprSyntax
        /// The tier and anchor it resolved to.
        let inference: BodyInference
        /// How it was resolved.
        let resolution: Resolution
        /// The imports of the call's file.
        let imports: Set<String>
    }

    /// Passes allowed before the collector fails.
    static let defaultMaxPasses = 50
    /// Reasons kept per function.
    static let viaLimit = 3

    /// The files, in `String <` order of their paths.
    let trees: [SourceFileSyntax]
    /// Each file's imports, parallel to `trees`.
    let imports: [Set<String>]
    /// The declared tiers of every file.
    let declared: EffectSymbolTable
    /// Signatures held by more than one inferred declaration.
    let shared: Set<FunctionSignature>
    /// Reads declared tiers, with the default attribute recognition.
    let parser = EffectAnnotationParser()

    /// Prepares inference over `trees`, already in path order.
    init(trees: [SourceFileSyntax]) {
        var table = EffectSymbolTable()
        for tree in trees {
            table.merge(source: tree, parser: parser)
        }
        self.trees = trees
        self.imports = trees.map(ImportCollector.imports(in:))
        self.declared = table
        self.shared = SignatureCensus.sharedSignatures(in: trees)
    }

    /// The enclosing function of `call`, if any.
    private static func enclosingFunction(of call: FunctionCallExprSyntax) -> FunctionDeclSyntax? {
        var current = call.parent
        while let node = current {
            if let function = node.as(FunctionDeclSyntax.self) {
                return function
            }
            current = node.parent
        }
        return nil
    }

    /// Whether another declaration declares `signature`, which suppresses
    /// inference for it.
    func isDeclared(_ signature: FunctionSignature) -> Bool {
        declared.entriesBySignature[signature] != nil || declared.isCollision(signature: signature)
    }

    /// Runs passes until one changes no tier, and returns the last map and
    /// how many passes ran; fails after `maxPasses`.
    func converge(
        maxPasses: Int
    ) throws(EffectInferenceError) -> (map: [FunctionSignature: BodyInference], passes: Int) {
        var map: [FunctionSignature: BodyInference] = [:]
        var passes = 0
        while passes < maxPasses {
            passes += 1
            let next = pass(previous: map)
            if next.mapValues(\.effect) == map.mapValues(\.effect) {
                return (next, passes)
            }
            map = next
        }
        throw EffectInferenceError.didNotConverge(maxPasses: maxPasses)
    }

    /// One more pass over the converged `map`, recording each resolved call
    /// under its enclosing function: the pass's results, and the calls.
    func explain(
        map: [FunctionSignature: BodyInference]
    ) -> (results: [FunctionSignature: BodyInference], calls: [SyntaxIdentifier: [ResolvedCall]]) {
        var results: [FunctionSignature: BodyInference] = [:]
        var calls: [SyntaxIdentifier: [ResolvedCall]] = [:]
        for (tree, fileImports) in zip(trees, imports) {
            let found = BodyEffectInferrer.inferEffects(in: tree, parser: parser) { call in
                guard let (inference, resolution) = resolve(call, imports: fileImports, previous: map) else {
                    return nil
                }
                if let function = Self.enclosingFunction(of: call) {
                    calls[function.id, default: []].append(ResolvedCall(
                        call: call,
                        inference: inference,
                        resolution: resolution,
                        imports: fileImports
                    ))
                }
                return inference
            }
            for (signature, inference) in found where isInferable(signature) {
                results[signature] = inference
            }
        }
        return (results, calls)
    }

    /// Up to `viaLimit` sorted, unique reasons among `calls` resolved at
    /// `tier`'s rank.
    func via(for tier: Effect, calls: [ResolvedCall]) -> [String] {
        let reasons = calls.filter { $0.inference.effect.rank == tier.rank }.map { resolved -> String in
            switch resolved.resolution {
            case .heuristic:
                return CallSiteEffectInferrer.inferenceReason(for: resolved.call, imports: resolved.imports)
                    ?? "a heuristic"

            case .callee(let signature):
                return "calls `\(signature.description)`"
            }
        }
        return Array(Set(reasons).sorted().prefix(Self.viaLimit))
    }

    /// One pass: every inferable declaration's result, with calls resolved
    /// against `previous`.
    private func pass(previous: [FunctionSignature: BodyInference]) -> [FunctionSignature: BodyInference] {
        var results: [FunctionSignature: BodyInference] = [:]
        for (tree, fileImports) in zip(trees, imports) {
            let found = BodyEffectInferrer.inferEffects(in: tree, parser: parser) { call in
                resolve(call, imports: fileImports, previous: previous)?.inference
            }
            for (signature, inference) in found where isInferable(signature) {
                results[signature] = inference
            }
        }
        return results
    }

    /// Whether a declaration with `signature` gets a tier of its own: no
    /// other declaration shares or declares it.
    private func isInferable(_ signature: FunctionSignature) -> Bool {
        shared.contains(signature) == false && isDeclared(signature) == false
    }

    /// The strict resolver: nothing for a collided signature (two or more
    /// annotations, even agreeing ones, as SwiftEffectInference's own
    /// resolver treats them); else the declared tier; else nothing for a
    /// shared signature; else the previous pass's tier or the heuristic's
    /// guess. The declared tier comes before the shared check: an
    /// annotation governs its signature whichever body a call reaches
    /// (those bodies are never inferred), and refusing shared signatures
    /// only stops merged inferred tiers spreading.
    private func resolve(
        _ call: FunctionCallExprSyntax,
        imports fileImports: Set<String>,
        previous: [FunctionSignature: BodyInference]
    ) -> (inference: BodyInference, resolution: Resolution)? {
        if let signature = FunctionSignature.from(call: call) {
            if declared.isCollision(signature: signature) {
                return nil
            }
            if let effect = declared.effect(for: signature) {
                return (BodyInference(effect: effect, depth: 0, anchor: .declared), .callee(signature))
            }
            if shared.contains(signature) {
                return nil
            }
            if let known = previous[signature] {
                return (known, .callee(signature))
            }
        }
        guard let guess = CallSiteEffectInferrer.infer(call: call, imports: fileImports) else {
            return nil
        }
        return (BodyInference(effect: guess, depth: 0, anchor: .heuristic), .heuristic)
    }
}
