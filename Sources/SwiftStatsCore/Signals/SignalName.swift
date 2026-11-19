//
//  SignalName.swift
//  SwiftStatsCore
//
//  The derived signals M3 computes (PRD §8).
//

/// A derived signal.
public enum SignalName: String, CaseIterable, Codable, Hashable, Sendable {
    /// Fix commits weighted by age: past bugs predict future ones.
    case bugProne = "bug-prone"
    /// Churn times complexity: complex code that keeps changing.
    case hotspot
    /// Old, unchanged, never-fixed complex code: lower priority elsewhere.
    case safeToLeave = "safe-to-leave"
    /// Code that changes often while its tests rarely do.
    case testsNotKeepingUp = "tests-not-keeping-up"
    /// Code touched by reverts or by fixes in quick succession.
    case unstableFixes = "unstable-fixes"

    /// The order reports list signals in.
    public static let reportOrder: [Self] = [.hotspot, .bugProne, .unstableFixes, .testsNotKeepingUp, .safeToLeave]

    /// The name a report heads the signal with.
    public var title: String {
        switch self {
        case .bugProne:
            "Bug-prone"

        case .hotspot:
            "Hotspots"

        case .safeToLeave:
            "Safe to leave"

        case .testsNotKeepingUp:
            "Tests not keeping up"

        case .unstableFixes:
            "Unstable fixes"
        }
    }

    /// Whether membership is the top share of candidates by score, rather
    /// than a fixed condition.
    var isRanked: Bool {
        self == .hotspot || self == .bugProne
    }
}
