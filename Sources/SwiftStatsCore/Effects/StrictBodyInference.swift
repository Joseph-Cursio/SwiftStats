//
//  StrictBodyInference.swift
//  SwiftStatsCore
//
//  Body inference with strict callee resolution (PRD §7.10). SwiftEffect-
//  Inference keys inferred tiers by signature and merges every declaration
//  that shares one, which spreads a tier to callers that never call the
//  declaration it came from. Here a call to a shared signature that no
//  annotation declares resolves to nothing, and an unqualified or `self.`
//  call to a package function this run infers takes only that function's
//  inferred tier, never a guess from its name. A call through another
//  receiver (`logger.info`, `transport.send`) may reach an external API
//  with the same signature, so it takes the higher of that tier and the
//  guess. Everything else (the lattice, the walk, the escaping-closure
//  rule, the heuristics) is SwiftEffectInference's own. Each pass reads
//  only the previous pass's map (Jacobi iteration), so file order can't
//  change the result. A pass's only inputs that change are the previous
//  pass's tiers, a callee not yet in the map counts as bottom, a guess is
//  the same every pass, and a body takes the upper bound of its calls, so
//  every pass is monotone: the map climbs from empty to the least fixed
//  point, through cycles too, and a guess never drops out of one. The loop
//  has no clock: it stops when a pass changes no tier, or fails the
//  collector after `maxPasses`.
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
    /// Signatures held by an inferred declaration, shared or not: a package
    /// function's body, never its name, decides an unqualified or `self.`
    /// call to it.
    let bodied: Set<FunctionSignature>
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
        let counts = SignatureCensus.counts(in: trees)
        self.shared = Set(counts.filter { $0.value > 1 }.keys)
        self.bodied = Set(counts.keys)
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

    /// Whether `call` is made through a receiver other than `self`, `Self`
    /// or `super`, such as `logger.info(…)` or `transport.send(…)`.
    private static func namesOtherReceiver(_ call: FunctionCallExprSyntax) -> Bool {
        guard var base = call.calledExpression.as(MemberAccessExprSyntax.self)?.base else {
            return false
        }
        while let inner = base.as(OptionalChainingExprSyntax.self)?.expression
            ?? base.as(ForceUnwrapExprSyntax.self)?.expression {
            base = inner
        }
        if base.is(SuperExprSyntax.self) {
            return false
        }
        guard let reference = base.as(DeclReferenceExprSyntax.self) else {
            return true
        }
        return ["self", "Self"].contains(reference.baseName.text) == false
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
    /// shared signature; else, for an unqualified or `self.` call to a
    /// package function this run infers, only the previous pass's tier
    /// (nothing while its body hasn't given one, or gives none); else the
    /// higher of that tier and the heuristic's guess, the guess on a tie.
    /// The declared tier comes before the shared check: an annotation
    /// governs its signature whichever body a call reaches (those bodies are
    /// never inferred), and refusing shared signatures only stops merged
    /// inferred tiers spreading. A signature alone can't tell
    /// `transport.send(_:)` or `logger.info(_:)` from a package function of
    /// that name, so a call through another receiver keeps its guess: a
    /// forwarding wrapper or a logging facade doesn't take the heuristic
    /// from every call of its signature. The guess is the same every pass
    /// and the tier only climbs, so each pass stays monotone; a recursive
    /// `updateTree` or a cycle through `insertNode` called unqualified takes
    /// its bodies' tier, not its name's.
    private func resolve(
        _ call: FunctionCallExprSyntax,
        imports fileImports: Set<String>,
        previous: [FunctionSignature: BodyInference]
    ) -> (inference: BodyInference, resolution: Resolution)? {
        var known: (inference: BodyInference, resolution: Resolution)?
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
            known = previous[signature].map { ($0, .callee(signature)) }
            if known != nil || bodied.contains(signature), Self.namesOtherReceiver(call) == false {
                return known
            }
        }
        let guess = CallSiteEffectInferrer.infer(call: call, imports: fileImports).map { effect in
            (inference: BodyInference(effect: effect, depth: 0, anchor: .heuristic), resolution: Resolution.heuristic)
        }
        guard let known, let guess else {
            return known ?? guess
        }
        return known.inference.effect.rank > guess.inference.effect.rank ? known : guess
    }
}
