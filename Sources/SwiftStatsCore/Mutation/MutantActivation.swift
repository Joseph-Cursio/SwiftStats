//
//  MutantActivation.swift
//  SwiftStatsCore
//
//  Whether a mutant's block ran in its run (M6, design §2 item 7), as a
//  results line's `activated` says: true, false, or absent when the run
//  showed neither or the line predates the key. A pass whose block didn't
//  run is a mutant with no coverage.
//

/// Whether a mutant's block ran.
enum MutantActivation: String, Sendable {
    /// The run reached mutated code, but not this block.
    case notRan
    /// The block ran.
    case ran
    /// The line doesn't say.
    case unknown

    /// The flag the scan JSON writes for it: true, false, or none.
    var flag: JSONFlag? {
        switch self {
        case .ran:
            JSONFlag(true)

        case .notRan:
            JSONFlag(false)

        case .unknown:
            nil
        }
    }

    /// The activation a line's `activated` flag gives; `.unknown` when it
    /// has none.
    init(_ flag: JSONFlag?) {
        switch flag?.value {
        case .some(true):
            self = .ran

        case .some(false):
            self = .notRan

        case .none:
            self = .unknown
        }
    }
}
