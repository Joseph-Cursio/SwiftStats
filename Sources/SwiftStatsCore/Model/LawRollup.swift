//
//  LawRollup.swift
//  SwiftStatsCore
//
//  Law-check counts over a production module or the project's production
//  part (PRD §7.11): the pairs of the scope's types by state. Absent from
//  test modules and the `tests` part, whose types are never subjects.
//

/// Law-check pairs counted over one scope.
public struct LawRollup: Codable, Hashable, Sendable {
    /// Pairs by state (`LawCheck.State` raw values).
    public let state: [String: Int]

    /// The counts over `checks`.
    init(_ checks: [LawCheck]) {
        state = checks.reduce(into: [:]) { counts, check in
            counts[check.state.rawValue, default: 0] += 1
        }
    }
}
