//
//  SignalName.swift
//  SwiftStatsCore
//
//  The derived signals (PRD §8), and the inputs each needs.
//

/// A derived signal.
public enum SignalName: String, CaseIterable, Codable, Hashable, Sendable {
    /// Functions with an algebraic suggestion whose mutants the tests don't
    /// kill: where a property test may pay off most.
    case bestPropertyTarget = "best-property-target"
    /// Fix commits weighted by age: past bugs predict future ones.
    case bugProne = "bug-prone"
    /// Cloned code that keeps changing, so each change is made in every copy.
    case cloneHotspot = "clone-hotspot"
    /// Clone classes where one copy changed since an earlier snapshot and
    /// another didn't: perhaps a fix made in one place only.
    case divergentClones = "divergent-clones"
    /// Functions where coverage, mutation and the module's test code agree
    /// the tests barely touch them: little run, few mutants killed, in a
    /// module with little test code.
    case genuinelyUnderTested = "genuinely-under-tested"
    /// Churn times complexity: complex code that keeps changing.
    case hotspot
    /// Pure, value-shaped functions with an algebraic shape and no
    /// suggestion of any tier: a template SwiftInferProperties may lack.
    case missingTemplate = "missing-template"
    /// Crash and data-race markers on code no test ran: crash or race
    /// candidates.
    case riskyUntested = "risky-untested"
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
    /// Clone classes whose mutants the tests kill in one copy and barely
    /// in another: copy the tests, or merge the code.
    case unevenCloneMutation = "uneven-clone-mutation"
    /// Clone classes with a copy the tests cover well and a copy they
    /// barely cover: copy the tests, or merge the code.
    case unevenCloneTesting = "uneven-clone-testing"
    /// Code touched by reverts or by fixes in quick succession.
    case unstableFixes = "unstable-fixes"
    /// Strong or Verified suggestions no property test checks.
    case untestedProperty = "untested-property"
    /// Functions the tests run but whose mutants they mostly don't kill, or
    /// kill only through suspect tests.
    case weakTests = "weak-tests"

    /// The order reports list signals in.
    public static let reportOrder: [Self] = [
        .hotspot, .bugProne, .unstableFixes, .testsNotKeepingUp, .safeToLeave,
        .untestedProperty, .toolDisagreement, .missingTemplate, .uncheckedLaws, .divergentClones, .cloneHotspot,
        .riskyUntested, .unevenCloneTesting, .weakTests, .genuinelyUnderTested, .bestPropertyTarget,
        .unevenCloneMutation
    ]

    /// The name a report heads the signal with.
    public var title: String {
        switch self {
        case .bestPropertyTarget:
            "Best property-test targets"

        case .bugProne:
            "Bug-prone"

        case .cloneHotspot:
            "Clone hotspots"

        case .divergentClones:
            "Divergent clones"

        case .genuinelyUnderTested:
            "Genuinely under-tested"

        case .hotspot:
            "Hotspots"

        case .missingTemplate:
            "Missing templates"

        case .riskyUntested:
            "Risky + untested"

        case .safeToLeave:
            "Safe to leave"

        case .testsNotKeepingUp:
            "Tests not keeping up"

        case .toolDisagreement:
            "Tool disagreements"

        case .uncheckedLaws:
            "Unchecked laws"

        case .unevenCloneMutation:
            "Uneven clone testing (mutation)"

        case .unevenCloneTesting:
            "Uneven clone testing"

        case .unstableFixes:
            "Unstable fixes"

        case .untestedProperty:
            "Untested properties"

        case .weakTests:
            "Weak tests"
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
    /// M5's signals list the M5 snapshot first, so a snapshot stored
    /// before M5 says so rather than naming a collector it never had; M6's
    /// list the M6 snapshot first likewise, then SwiftMutator, then
    /// coverage (best property-test target SwiftInferProperties instead),
    /// and genuinely under-tested also needs results that list code no
    /// test ran; uneven clone testing's mutation part lists the clone
    /// detector before SwiftMutator, as its coverage part lists it before
    /// coverage.
    var requirements: [SignalRequirement] {
        let mutation = SignalRequirement.collector(MutationAdapter.name)
        let effects = SignalRequirement.collector(EffectCollector.name)
        let properties = SignalRequirement.collector(SwiftInferPropertiesAdapter.name)
        let coverage = SignalRequirement.collector(CoverageAdapter.name)
        let clones = SignalRequirement.collector(SwiftCloneDetectorAdapter.name)
        return switch self {
        case .bestPropertyTarget:
            [.m6Snapshot, mutation, properties]

        case .bugProne, .hotspot, .safeToLeave, .testsNotKeepingUp, .unstableFixes:
            [.history]

        case .cloneHotspot:
            [clones, .history]

        case .divergentClones:
            [.history, .m4Snapshot]

        case .genuinelyUnderTested:
            [.m6Snapshot, mutation, coverage, .notCoveredListed]

        case .missingTemplate:
            [effects, properties]

        case .riskyUntested:
            [.m5Snapshot, coverage, .collector(SwiftProjectLintAdapter.name)]

        case .toolDisagreement:
            [properties, effects]

        case .uncheckedLaws:
            [.m4Snapshot]

        case .unevenCloneMutation:
            [.m6Snapshot, clones, mutation]

        case .unevenCloneTesting:
            [.m5Snapshot, clones, coverage]

        case .untestedProperty:
            [properties]

        case .weakTests:
            [.m6Snapshot, mutation, coverage]
        }
    }
}
