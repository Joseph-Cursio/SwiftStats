//
//  SignalEngine+Index.swift
//  SwiftStatsCore
//
//  M7's signals in the engine (design §8): hidden coupling, dead but
//  tested and test-only production code, computed from the T1 results a
//  snapshot holds. Each names only its own missing inputs: the index rows
//  for hidden coupling and test-only production code, the dead-code rows,
//  then the mutation rows, for dead but tested. A left-out M7 signal
//  states its rule without the funnel.
//

extension SignalEngine {
    /// M7's signal `signal` computed from `inputs`, hidden coupling with
    /// the limits `thresholds` set; nil when the input its requirements
    /// don't check is missing.
    static func indexComputation(
        _ signal: SignalName,
        inputs: SignalInputs,
        thresholds: SignalThresholds
    ) -> SignalComputation? {
        switch signal {
        case .hiddenCoupling:
            HiddenCoupling.compute(inputs, thresholds: thresholds)

        case .deadButTested:
            DeadButTested.compute(inputs)

        default:
            TestOnlyProduction.compute(inputs)
        }
    }

    /// The rule M7's signal `signal` states when left out, with the limits
    /// `thresholds` set for hidden coupling: the design's rule text without
    /// the funnel.
    static func indexRule(_ signal: SignalName, thresholds: SignalThresholds) -> String {
        switch signal {
        case .hiddenCoupling:
            HiddenCoupling.rule(thresholds: thresholds)

        case .deadButTested:
            DeadButTested.rule

        default:
            TestOnlyProduction.rule
        }
    }

    /// Why M7's signal `signal` found no input its requirements check:
    /// for dead but tested, the dead-code rows, then the mutation rows;
    /// for the others, the index rows.
    static func indexMissingInput(_ signal: SignalName, _ snapshot: StoredSnapshot) -> String {
        guard signal == .deadButTested else {
            return "the snapshot holds no index rows"
        }
        return snapshot.deadCode == nil ? "the snapshot holds no dead-code rows" : "the snapshot holds no mutation rows"
    }
}
