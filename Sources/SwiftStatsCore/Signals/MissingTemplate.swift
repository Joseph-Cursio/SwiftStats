//
//  MissingTemplate.swift
//  SwiftStatsCore
//
//  Missing template (PRD §8): a function that looks like a law's subject
//  but has no suggestion, which may reveal a template SwiftInferProperties
//  lacks. The pool is the production `func`s outside generated files, not
//  nested in another record, that SwiftEffectInference calls pure (or pure
//  but for errors they throw), that are value-shaped and have an algebraic
//  shape. Purity alone doesn't check mutation, so the value shape stands
//  in for it. Every one with no algebraic suggestion of any tier attached,
//  Advisory rows included, is listed, scored by its body lines; the signal
//  isn't ranked. A suggestion covers its partner too (the inverse of a
//  round trip, the other side of a differential equivalence), since a
//  template that names the partner already exists. Items sort by shape, then body lines, shortest first.
//

/// The missing-template signal.
enum MissingTemplate {
    /// The order shapes list in.
    static let shapeOrder: [EffectFacts.Shape] = [.endomorphism, .binary, .selfReturning, .predicate]

    /// The rule as reports state it, before the functions are counted.
    static let rule = "pure, value-shaped production functions with an algebraic shape and no algebraic "
        + "suggestion of any tier"

    /// The signal over `snapshot`.
    static func compute(_ snapshot: StoredSnapshot) -> SignalComputation {
        let suggested = Set(snapshot.candidates.flatMap { candidate -> [String] in
            guard candidate.population == .algebraic, let location = candidate.location,
                  location.attachedTo == .function else {
                return []
            }
            return [location.owner, candidate.partnerKey].compactMap(\.self)
        })
        let valueShaped = ProductionFunctions(snapshot).rows.filter { row in
            guard row.kind == .function, row.parentKey == nil, let effect = row.facts?.effect,
                  effect.purity != .refuted else {
                return false
            }
            return effect.function?.valueShaped == true
        }
        let pool = valueShaped.filter { $0.facts?.effect?.function?.shape != nil }
        let shapeless = valueShaped.count - pool.count
        return SignalComputation(
            rule: rule + "; \(shapeless) pure, value-shaped functions have no algebraic shape and are left out",
            candidates: pool.count,
            scored: pool.compactMap { row in
                guard suggested.contains(row.key) == false, let effect = row.facts?.effect,
                      let shape = effect.function?.shape else {
                    return nil
                }
                return item(row, effect: effect, shape: shape)
            }
        )
    }

    /// The item for `row`, of `shape`, scored by its body lines.
    private static func item(_ row: FunctionRow, effect: StoredEffect, shape: EffectFacts.Shape) -> SignalScore {
        let draft = SignalItem.Draft(
            subject: row.key,
            file: row.file,
            line: row.startLine,
            effect: SignalItem.Effect(
                inferred: effect.function?.inferred,
                purity: effect.purity,
                source: effect.source,
                shape: shape
            ),
            function: SignalItem.Function(bodyLines: row.bodyLines, cognitive: row.cognitive)
        )
        let order = SignalSortKey([
            .number(Double(shapeOrder.firstIndex(of: shape) ?? shapeOrder.count)),
            .number(Double(row.bodyLines)),
            .text(row.key),
            .text(row.file),
            .number(Double(row.startLine))
        ])
        return SignalScore(draft, score: Double(row.bodyLines), sortKey: order)
    }
}
