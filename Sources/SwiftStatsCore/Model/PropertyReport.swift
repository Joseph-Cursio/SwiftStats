//
//  PropertyReport.swift
//  SwiftStatsCore
//
//  What the SwiftInferProperties collector produced (PRD §7.11): every
//  suggestion of `swift-infer index`, run once per production target and
//  merged, with what the merge dropped and the SwiftEffectInference
//  revision the binary was built with. Absent when the collector didn't run.
//

/// SwiftInferProperties' suggestions for one scan.
public struct PropertyReport: Codable, Hashable, Sendable {
    /// The candidates, sorted by file, line, identity, then population; a
    /// candidate with no location sorts first.
    public let candidates: [PropertyCandidate]
    /// Rows dropped because another target wrote the same suggestion at the
    /// same location, equal but for timestamps.
    public let crossTargetDuplicates: Int
    /// Rows dropped because another target wrote the same suggestion at the
    /// same location with different fields; the kept row has a structural
    /// blocker, else a type shape, else the lower score, else the first
    /// target's name.
    public let crossTargetConflicts: Int
    /// Identities that targets found at more than one location.
    public let identityCollisions: Int
    /// The SwiftEffectInference revision in the `workspace-state.json` of
    /// the SwiftPM build directory holding `swift-infer`, possibly stale
    /// after a resolve without a rebuild; nil outside a build directory.
    public let seiRevision: String?

    /// Creates a report. Fields are documented on their properties.
    public init(
        candidates: [PropertyCandidate],
        crossTargetDuplicates: Int,
        crossTargetConflicts: Int,
        identityCollisions: Int,
        seiRevision: String?
    ) {
        self.candidates = candidates
        self.crossTargetDuplicates = crossTargetDuplicates
        self.crossTargetConflicts = crossTargetConflicts
        self.identityCollisions = identityCollisions
        self.seiRevision = seiRevision
    }
}
