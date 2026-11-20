//
//  ToolDisagreement.swift
//  SwiftStatsCore
//
//  Tool disagreement (PRD §8): SwiftInferProperties suggests idempotence
//  for a function whose own body SwiftStats' SwiftEffectInference run, by
//  strict resolution, infers `non_idempotent`. The pool is the algebraic
//  suggestions of the value class (`idempotence`, `idempotence-lifted`,
//  `binary-idempotence`, `mutator-idempotence`) and the replay class
//  (`replay-idempotence`). One is listed when it attaches to a production
//  `func` outside generated files whose signature is its own, whose tier
//  isn't declared, and whose body gives `non_idempotent`; the rule counts
//  what each of those steps removed. Replay rows list first, then those
//  resting on annotations alone, then by SwiftInferProperties' score.
//

/// The tool-disagreement signal.
enum ToolDisagreement {
    /// What removed suggestions from the list, each counted once.
    struct Funnel {
        /// Their function's signature is shared, so no tier is its own.
        var shared = 0
        /// Another declaration annotates the signature, or the function
        /// declares its tier, or declares it unknown, or conflicts.
        var declared = 0
        /// They attach to no production `func` outside generated files.
        var notFunction = 0
        /// The body gives no tier.
        var noTier = 0
        /// The body gives a tier other than `non_idempotent`.
        var otherTier = 0
    }

    /// The value-idempotence templates.
    static let valueTemplates: Set = ["binary-idempotence", "idempotence", "idempotence-lifted", "mutator-idempotence"]
    /// The replay-idempotence template, SwiftEffectInference's own notion.
    static let replayTemplate = "replay-idempotence"
    /// Characters of a revision a rule shows.
    private static let revisionLength = 10

    /// The rule as reports state it, before the suggestions are counted.
    static let rule = "idempotence suggestions on production functions whose own body SwiftEffectInference "
        + "infers non_idempotent, by strict resolution"

    /// The signal over `snapshot`.
    static func compute(_ snapshot: StoredSnapshot) -> SignalComputation {
        let functions = ProductionFunctions(snapshot)
        let pool = snapshot.candidates.filter { candidate in
            candidate.population == .algebraic
                && (valueTemplates.contains(candidate.template) || candidate.template == replayTemplate)
        }
        var funnel = Funnel()
        var scored: [SignalScore] = []
        for candidate in pool {
            guard let row = functions.row(of: candidate), row.kind == .function,
                  let effect = row.facts?.effect, let function = effect.function else {
                funnel.notFunction += 1
                continue
            }
            switch function.inference {
            case .ambiguous:
                funnel.shared += 1
                continue

            case .annotated, .shadowed:
                funnel.declared += 1
                continue

            case .unique, nil:
                break
            }
            if [.declared, .conflicting, .unknown].contains(effect.source) {
                funnel.declared += 1
            } else if let inferred = function.inferred {
                if inferred.tier == .nonIdempotent {
                    scored.append(item(candidate, row: row, effect: effect, inferred: inferred))
                } else {
                    funnel.otherTier += 1
                }
            } else {
                funnel.noTier += 1
            }
        }
        return SignalComputation(
            rule: rule(funnel, total: pool.count, snapshot: snapshot),
            candidates: pool.count,
            scored: scored
        )
    }

    /// The item for `candidate` on `row`, whose body infers `inferred`:
    /// scored by SwiftInferProperties' score, replay rows first, then
    /// annotation-anchored ones, then by score, highest first.
    private static func item(
        _ candidate: PropertyCandidate,
        row: FunctionRow,
        effect: StoredEffect,
        inferred: EffectFacts.Inferred
    ) -> SignalScore {
        let draft = SignalItem.Draft(
            subject: row.key,
            file: row.file,
            line: row.startLine,
            property: SignalItem.Property(candidate),
            effect: SignalItem.Effect(inferred: inferred, purity: effect.purity, source: effect.source, shape: nil)
        )
        let score = Double(candidate.score)
        let order = SignalSortKey([
            .number(candidate.template == replayTemplate ? 0 : 1),
            .number(inferred.anchor == .declared ? 0 : 1),
            .number(-score),
            .text(row.key),
            .text(row.file),
            .number(Double(row.startLine)),
            .text(candidate.identity)
        ])
        return SignalScore(draft, score: score, sortKey: order)
    }

    /// The rule with what each step removed of `total` suggestions, and
    /// the SwiftEffectInference revisions of both tools.
    private static func rule(_ funnel: Funnel, total: Int, snapshot: StoredSnapshot) -> String {
        let removed = "of \(total) suggestions, removed: \(funnel.shared) shared signature, "
            + "\(funnel.declared) shadowed or declared, \(funnel.notFunction) not a production func or unmapped, "
            + "\(funnel.noTier) no body-inferred tier, \(funnel.otherTier) inferred tier not non_idempotent"
        let calibrates = "SwiftInferProperties proposes idempotence only for functions its SwiftEffectInference "
            + "oracle calls pure, so this list mainly calibrates SwiftEffectInference's heuristics and receiver "
            + "resolution"
        let own = snapshot.info.collectors.first { $0.name == EffectCollector.name }?.version
        let revisions = "SwiftEffectInference \(revision(own)) here, "
            + "\(revision(snapshot.scanFacts?.sipSeiRevision)) in swift-infer (possibly stale after a resolve "
            + "without a rebuild)"
        return "\(rule); \(removed). \(calibrates). \(revisions)"
    }

    /// `revision` shortened, or "unknown".
    private static func revision(_ revision: String?) -> String {
        revision.map { String($0.prefix(revisionLength)) } ?? "unknown"
    }
}
