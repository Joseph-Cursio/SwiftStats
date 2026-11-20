//
//  PropertyRollup.swift
//  SwiftStatsCore
//
//  Property-test suggestion counts over a module or a part of the project
//  (PRD §7.11): candidates by tier as written, and how many attach to a
//  function. A candidate counts in the scope holding its file; one with no
//  location, or in a file the scan didn't cover, counts in the project's
//  production part only, as the report's unmapped list shows it. Absent
//  when SwiftInferProperties didn't run, and on scopes holding no candidate.
//

/// Property-test suggestions counted over one scope.
public struct PropertyRollup: Codable, Hashable, Sendable {
    /// Candidates by tier as written (`Strong`, `Advisory`, …).
    public let tier: [String: Int]
    /// Candidates attached to a function record.
    public let mapped: Int
    /// Candidates attached to none.
    public let unmapped: Int

    /// The counts over the candidates whose files are among `paths`, and,
    /// when `countsUnplaced` is set, those with no location or in a file
    /// the scan didn't cover; nil when none counts.
    init?(_ candidates: [PropertyCandidate], in paths: Set<String>, countsUnplaced: Bool) {
        let counted = candidates.filter { candidate in
            guard let location = candidate.location, location.attachedTo != .unscanned else {
                return countsUnplaced
            }
            return paths.contains(location.file)
        }
        guard counted.isEmpty == false else {
            return nil
        }
        tier = counted.reduce(into: [:]) { counts, candidate in
            counts[candidate.tier, default: 0] += 1
        }
        mapped = counted.filter { $0.unmapped == nil }.count
        unmapped = counted.count - mapped
    }
}
