//
//  EffectInferenceError.swift
//  SwiftStatsCore
//
//  Why the side-effect collector couldn't produce results. It fails that
//  collector (PRD §6.5), not the scan.
//

/// A side-effect run that didn't finish.
enum EffectInferenceError: Error, Equatable, CustomStringConvertible {
    /// Body inference still changed tiers after this many passes.
    case didNotConverge(maxPasses: Int)

    /// A one-line explanation for the collector's status.
    var description: String {
        switch self {
        case .didNotConverge(let maxPasses):
            return "body inference did not converge in \(maxPasses) passes"
        }
    }
}
