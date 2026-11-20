//
//  PropertyReport.swift
//  SwiftStatsCore
//
//  What the SwiftInferProperties collector produced (PRD §7.11): every
//  suggestion of `swift-infer index`, run once per production target and
//  merged, with what the merge dropped, what the package's own decisions
//  and verify evidence hold that no candidate matches, which of those files
//  were read, and the SwiftEffectInference revision the binary was built
//  with. Absent when the collector didn't run.
//

/// SwiftInferProperties' suggestions for one scan.
public struct PropertyReport: Codable, Hashable, Sendable {
    /// The package's `.swiftinfer/` files joined to the candidates, each as
    /// `sha256:<hex>`; nil when absent or unreadable, as in an exported revision.
    public struct JoinInputs: Codable, Hashable, Sendable {
        /// `decisions.json`.
        public let decisions: String?
        /// `interaction-decisions.json`.
        public let interactionDecisions: String?
        /// `verify-evidence.json`.
        public let verifyEvidence: String?

        /// Creates the inputs. Fields are documented on their properties.
        public init(decisions: String?, interactionDecisions: String?, verifyEvidence: String?) {
            self.decisions = decisions
            self.interactionDecisions = interactionDecisions
            self.verifyEvidence = verifyEvidence
        }
    }

    /// The candidates, sorted by file, line, identity, then population; a
    /// candidate with no location sorts first.
    public let candidates: [PropertyCandidate]
    /// Decision records, in both decisions files, naming no candidate of
    /// their population; nil when neither file was read.
    public let orphanDecisions: Int?
    /// Verify records naming no candidate; nil when the file wasn't read.
    public let orphanVerifyRecords: Int?
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
    /// The `.swiftinfer/` files the joins read.
    public let joinInputs: JoinInputs
    /// The SwiftEffectInference revision in the `workspace-state.json` of
    /// the SwiftPM build directory holding `swift-infer`, possibly stale
    /// after a resolve without a rebuild; nil outside a build directory.
    public let seiRevision: String?

    /// Creates a report. Fields are documented on their properties.
    public init(
        candidates: [PropertyCandidate],
        orphanDecisions: Int?,
        orphanVerifyRecords: Int?,
        crossTargetDuplicates: Int,
        crossTargetConflicts: Int,
        identityCollisions: Int,
        joinInputs: JoinInputs,
        seiRevision: String?
    ) {
        self.candidates = candidates
        self.orphanDecisions = orphanDecisions
        self.orphanVerifyRecords = orphanVerifyRecords
        self.crossTargetDuplicates = crossTargetDuplicates
        self.crossTargetConflicts = crossTargetConflicts
        self.identityCollisions = identityCollisions
        self.joinInputs = joinInputs
        self.seiRevision = seiRevision
    }
}
