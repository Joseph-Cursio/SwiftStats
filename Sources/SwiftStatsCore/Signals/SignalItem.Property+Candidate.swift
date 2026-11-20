//
//  SignalItem.Property+Candidate.swift
//  SwiftStatsCore
//
//  The suggestion payload of an item, read from a stored candidate.
//

extension SignalItem.Property {
    /// The payload of `candidate`.
    init(_ candidate: PropertyCandidate) {
        self.init(
            identity: candidate.identity,
            template: candidate.template,
            tier: candidate.tier,
            score: candidate.score,
            verified: candidate.verification?.judgement?.verified == true,
            blocked: candidate.blocked,
            decision: candidate.decision,
            partner: candidate.partner,
            testedBy: candidate.testedBy
        )
    }
}
