//
//  SignalName.swift
//  SwiftStatsCore
//
//  The derived signals (PRD §8), and the inputs each needs.
//

/// A derived signal.
public enum SignalName: String, CaseIterable, Codable, Hashable, Sendable {
    /// Fix commits weighted by age: past bugs predict future ones.
    case bugProne = "bug-prone"
    /// Cloned code that keeps changing, so each change is made in every copy.
    case cloneHotspot = "clone-hotspot"
    /// Clone classes where one copy changed since an earlier snapshot and
    /// another didn't: perhaps a fix made in one place only.
    case divergentClones = "divergent-clones"
    /// Churn times complexity: complex code that keeps changing.
    case hotspot
    /// Pure, value-shaped functions with an algebraic shape and no
    /// suggestion of any tier: a template SwiftInferProperties may lack.
    case missingTemplate = "missing-template"
    /// Old, unchanged, never-fixed complex code: lower priority elsewhere.
    case safeToLeave = "safe-to-leave"
    /// Code that changes often while its tests rarely do.
    case testsNotKeepingUp = "tests-not-keeping-up"
    /// Idempotence suggested for a function whose own body
    /// SwiftEffectInference infers `non_idempotent`.
    case toolDisagreement = "tool-disagreement"
    /// Types with a hand-written witness for a conformance the kit checks,
    /// which no test checks.
    case uncheckedLaws = "unchecked-laws"
    /// Code touched by reverts or by fixes in quick succession.
    case unstableFixes = "unstable-fixes"
    /// Strong or Verified suggestions no property test checks.
    case untestedProperty = "untested-property"

    /// The order reports list signals in.
    public static let reportOrder: [Self] = [
        .hotspot, .bugProne, .unstableFixes, .testsNotKeepingUp, .safeToLeave,
        .untestedProperty, .toolDisagreement, .missingTemplate, .uncheckedLaws, .divergentClones, .cloneHotspot
    ]

    /// The name a report heads the signal with.
    public var title: String {
        switch self {
        case .bugProne:
            "Bug-prone"

        case .cloneHotspot:
            "Clone hotspots"

        case .divergentClones:
            "Divergent clones"

        case .hotspot:
            "Hotspots"

        case .missingTemplate:
            "Missing templates"

        case .safeToLeave:
            "Safe to leave"

        case .testsNotKeepingUp:
            "Tests not keeping up"

        case .toolDisagreement:
            "Tool disagreements"

        case .uncheckedLaws:
            "Unchecked laws"

        case .unstableFixes:
            "Unstable fixes"

        case .untestedProperty:
            "Untested properties"
        }
    }

    /// Whether membership is the top share of candidates by score, rather
    /// than a fixed condition.
    var isRanked: Bool {
        self == .hotspot || self == .bugProne || self == .cloneHotspot
    }

    /// The inputs the signal needs; without one it is left out. A signal
    /// needing several collectors names the first that didn't run.
    /// Divergent clones also needs an earlier snapshot with clone data,
    /// which the workspace looks for, and git's account of what changed.
    var requirements: [SignalRequirement] {
        let effects = SignalRequirement.collector(EffectCollector.name)
        let properties = SignalRequirement.collector(SwiftInferPropertiesAdapter.name)
        return switch self {
        case .bugProne, .hotspot, .safeToLeave, .testsNotKeepingUp, .unstableFixes:
            [.history]

        case .cloneHotspot:
            [.collector(SwiftCloneDetectorAdapter.name), .history]

        case .divergentClones:
            [.history, .m4Snapshot]

        case .missingTemplate:
            [effects, properties]

        case .toolDisagreement:
            [properties, effects]

        case .uncheckedLaws:
            [.m4Snapshot]

        case .untestedProperty:
            [properties]
        }
    }
}
