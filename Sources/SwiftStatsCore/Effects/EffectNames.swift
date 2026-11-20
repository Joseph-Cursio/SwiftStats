//
//  EffectNames.swift
//  SwiftStatsCore
//
//  SwiftStats' names for SwiftEffectInference's values. Its enums have no
//  raw values ("not a stable wire format"), so each is mapped here, and the
//  scan JSON never depends on how the library spells a case.
//

import SwiftEffectInference

/// Maps SwiftEffectInference's values to the names SwiftStats records.
enum EffectNames {
    /// The tier of `effect`.
    static func tier(of effect: Effect) -> EffectFacts.Tier {
        switch effect {
        case .pure:
            return .pure

        case .observational:
            return .observational

        case .idempotent:
            return .idempotent

        case .externallyIdempotent:
            return .externallyIdempotent

        case .nonIdempotent:
            return .nonIdempotent
        }
    }

    /// The deduplication key's parameter of an `externally_idempotent` effect.
    static func keyParameter(of effect: Effect) -> String? {
        if case .externallyIdempotent(let keyParameter) = effect {
            return keyParameter
        }
        return nil
    }

    /// The name of `verdict`.
    static func purity(of verdict: PurityVerdict) -> EffectFacts.Purity {
        switch verdict {
        case .pure:
            return .pure

        case .pureButPartial:
            return .pureButPartial

        case .refuted:
            return .refuted
        }
    }

    /// The name of `anchor`.
    static func anchor(of anchor: BodyInference.Anchor) -> EffectFacts.Anchor {
        switch anchor {
        case .declared:
            return .declared

        case .heuristic:
            return .heuristic
        }
    }

    /// `refutation`'s outer case, innermost cause and description.
    static func refutation(_ refutation: PurityRefutation) -> EffectFacts.Refutation {
        EffectFacts.Refutation(
            case: caseName(of: refutation),
            root: caseName(of: rootCause(of: refutation)),
            detail: refutation.description
        )
    }

    /// The innermost cause of `refutation`, following `cause:` chains.
    private static func rootCause(of refutation: PurityRefutation) -> PurityRefutation {
        switch refutation {
        case let .refutingDefaultArgument(_, cause), let .refutingConstruction(_, _, cause):
            return rootCause(of: cause)

        default:
            return refutation
        }
    }

    /// The case name of `refutation`, as the library spells it.
    private static func caseName(of refutation: PurityRefutation) -> String {
        switch refutation {
        case .noBody:
            return "noBody"

        case .declaredAsync:
            return "declaredAsync"

        case .declaredThrows:
            return "declaredThrows"

        case .propagatedTry:
            return "propagatedTry"

        case .refutingDefaultArgument:
            return "refutingDefaultArgument"

        case .refutingConstruction:
            return "refutingConstruction"

        case .sideEffectMarker, .nondeterministicMarker, .nondeterminismSource,
            .fileRead, .partiality, .mutatesCapturedState, .notAGetter:
            return markerCaseName(of: refutation)
        }
    }

    /// The case name of a refutation that names what it found.
    private static func markerCaseName(of refutation: PurityRefutation) -> String {
        switch refutation {
        case .sideEffectMarker:
            return "sideEffectMarker"

        case .nondeterministicMarker:
            return "nondeterministicMarker"

        case .nondeterminismSource:
            return "nondeterminismSource"

        case .fileRead:
            return "fileRead"

        case .partiality:
            return "partiality"

        case .mutatesCapturedState:
            return "mutatesCapturedState"

        case .notAGetter:
            return "notAGetter"

        default:
            return "unnamed"
        }
    }
}
