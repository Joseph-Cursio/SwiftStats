//
//  PropertyJoins.swift
//  SwiftStatsCore
//
//  Joins SwiftInferProperties' suggestions to the scanned package's own
//  `.swiftinfer/` files (PRD §7.11), never the copy the tool ran in: the
//  decisions in `decisions.json` (algebraic rows) and
//  `interaction-decisions.json` (interaction rows), and the verify evidence
//  in `verify-evidence.json`. Those files name a suggestion by its hash
//  without `0x`; the first record of a hash wins, as in the tool's own
//  lookup. Evidence is fresh when its subject fingerprint and the row's are
//  both present and equal, and only fresh evidence verifies or disproves.
//  An interaction row carries no fingerprint in the index (the tool
//  computes it apart), so evidence naming one leaves freshness undecided.
//  An absent file, as in an exported revision, joins nothing and leaves its
//  fields nil; an unreadable one does the same, with a warning. Records
//  naming no candidate are counted, and each file read is recorded by hash.
//

import Foundation

/// The package's decisions and verify evidence, ready to join.
struct PropertyJoins {
    /// One decisions file's records.
    private struct File<Record: Decodable>: Decodable {
        /// The records, in file order.
        let records: [Record]
    }

    /// A record of `decisions.json`.
    private struct DecisionRecord: Decodable {
        /// The suggestion's hash, without `0x`.
        let identityHash: String
        /// The decision, written `acceptedAsConformance` for a conformance.
        let decision: PropertyCandidate.Decision
    }

    /// A decision as `interaction-decisions.json` writes it.
    private enum InteractionDecision: String, Decodable {
        /// Accepted.
        case accepted
        /// Accepted as a conformance, hyphenated in this file.
        case asConformance = "accepted-as-conformance"
        /// Rejected.
        case rejected
        /// Skipped.
        case skipped

        /// The decision it records.
        var decision: PropertyCandidate.Decision {
            switch self {
            case .accepted:
                return .accepted

            case .asConformance:
                return .asConformance

            case .rejected:
                return .rejected

            case .skipped:
                return .skipped
            }
        }
    }

    /// A record of `interaction-decisions.json`.
    private struct InteractionDecisionRecord: Decodable {
        /// The suggestion's hash, without `0x`.
        let identityHash: String
        /// The decision.
        let decision: InteractionDecision
    }

    /// A record of `verify-evidence.json`.
    private struct EvidenceRecord: Decodable {
        /// The suggestion's hash, without `0x`.
        let identityHash: String
        /// The run's outcome.
        let outcome: PropertyCandidate.VerifyOutcome
        /// The hash of the subject's body the run measured; nil in records
        /// older than fingerprints.
        let subjectFingerprint: String?
    }

    /// One file's records by hash: every record's hash, for counting
    /// orphans, and the first record's value for each hash.
    private struct Lookup<Value> {
        /// Every record's hash, normalised, in file order.
        let hashes: [String]
        /// The first record's value for each normalised hash.
        let values: [String: Value]

        /// The lookup over `records`, hashed by `hash` and valued by `value`.
        init<Record>(_ records: [Record], hash: (Record) -> String, value: (Record) -> Value) {
            hashes = records.map { PropertyJoins.normalised(hash($0)) }
            values = Dictionary(zip(hashes, records.map(value))) { first, _ in first }
        }

        /// How many records name none of `identities`.
        func orphans(among identities: Set<String>) -> Int {
            hashes.filter { identities.contains($0) == false }.count
        }
    }

    /// The prefix of an identity as the index writes it.
    private static let hexPrefix = "0x"
    /// The directory holding the files, under the package root.
    static let directory = ".swiftinfer"
    /// The algebraic rows' decisions.
    static let decisionsFile = "decisions.json"
    /// The interaction rows' decisions.
    static let interactionDecisionsFile = "interaction-decisions.json"
    /// The verify evidence.
    static let verifyEvidenceFile = "verify-evidence.json"
    /// The points fresh `measured-bothPass` evidence adds to a score.
    private static let bothPassWeight = 50
    /// The lowest score of the Strong band.
    private static let strongScore = 75
    /// The tier written on a row no test can run as written.
    private static let advisory = "Advisory"

    /// The files read, by hash.
    let inputs: PropertyReport.JoinInputs
    /// A warning for each file present but unreadable.
    let warnings: [ScanWarning]
    /// `decisions.json`; nil when absent or unreadable.
    private let decisions: Lookup<PropertyCandidate.Decision>?
    /// `interaction-decisions.json`; nil when absent or unreadable.
    private let interactionDecisions: Lookup<PropertyCandidate.Decision>?
    /// `verify-evidence.json`; nil when absent or unreadable.
    private let evidence: Lookup<EvidenceRecord>?

    /// The `.swiftinfer/` files of the package at `root`.
    init(root: URL) {
        var problems: [ScanWarning] = []
        let algebraic = Self.load(Self.decisionsFile, of: DecisionRecord.self, root: root, warnings: &problems)
        let interaction = Self.load(
            Self.interactionDecisionsFile,
            of: InteractionDecisionRecord.self,
            root: root,
            warnings: &problems
        )
        let verify = Self.load(Self.verifyEvidenceFile, of: EvidenceRecord.self, root: root, warnings: &problems)
        decisions = algebraic.map { Lookup($0.records, hash: \.identityHash, value: \.decision) }
        interactionDecisions = interaction.map { Lookup($0.records, hash: \.identityHash, value: \.decision.decision) }
        evidence = verify.map { Lookup($0.records, hash: \.identityHash) { $0 } }
        inputs = PropertyReport.JoinInputs(
            decisions: algebraic?.hash,
            interactionDecisions: interaction?.hash,
            verifyEvidence: verify?.hash
        )
        warnings = problems
    }

    /// `identity` as the files write it: no `0x`, uppercase.
    static func normalised(_ identity: String) -> String {
        let hex = identity.lowercased().hasPrefix(hexPrefix) ? identity.dropFirst(hexPrefix.count) : Substring(identity)
        return hex.uppercased()
    }

    /// The records of the file `name` in the package at `root`, and its
    /// `sha256:` hash; nil, with a warning when present, if it can't be read.
    private static func load<Record: Decodable>(
        _ name: String,
        of _: Record.Type,
        root: URL,
        warnings: inout [ScanWarning]
    ) -> (records: [Record], hash: String)? {
        let path = "\(directory)/\(name)"
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(File<Record>.self, from: data)
            return (file.records, "sha256:" + ContentHash.sha256(data))
        } catch {
            warnings.append(ScanWarning(
                file: path,
                message: "not readable, so SwiftInferProperties' suggestions aren't joined to it: \(error)"
            ))
            return nil
        }
    }

    /// What `record` says of `candidate`, its row's subject fingerprint
    /// being `fingerprint`; nil when a record names an interaction row,
    /// whose fingerprint the index doesn't carry.
    private static func judgement(
        of record: EvidenceRecord?,
        on candidate: PropertyCandidate,
        fingerprint: String?
    ) -> PropertyCandidate.Judgement? {
        guard let record else {
            return PropertyCandidate.Judgement(fresh: false, verified: false, disproven: false)
        }
        guard candidate.population == .algebraic else {
            return nil
        }
        let fresh = record.subjectFingerprint != nil && record.subjectFingerprint == fingerprint
        let lifted = candidate.tier != advisory && candidate.score + bothPassWeight >= strongScore
        return PropertyCandidate.Judgement(
            fresh: fresh,
            verified: fresh && record.outcome == .measuredBothPass && lifted,
            disproven: fresh && record.outcome == .measuredDefaultFails
        )
    }

    /// `candidate` joined to the decisions and verify evidence, its row's
    /// subject fingerprint being `fingerprint`.
    func joined(_ candidate: PropertyCandidate, fingerprint: String?) -> PropertyCandidate {
        var joined = candidate
        let hash = Self.normalised(candidate.identity)
        switch candidate.population {
        case .algebraic:
            joined.decision = decisions?.values[hash]

        case .interaction:
            joined.decision = interactionDecisions?.values[hash]
        }
        joined.verification = evidence.map { lookup in
            let record = lookup.values[hash]
            return PropertyCandidate.Verification(
                outcome: record?.outcome,
                judgement: Self.judgement(of: record, on: candidate, fingerprint: fingerprint)
            )
        }
        return joined
    }

    /// The records naming no candidate among `candidates`: decision records
    /// of either file naming no candidate of their population, nil when
    /// neither file was read; verify records naming none at all, nil when
    /// that file wasn't read.
    func orphans(among candidates: [PropertyCandidate]) -> (decisions: Int?, verifyRecords: Int?) {
        let algebraic = Set(candidates.filter { $0.population == .algebraic }.map { Self.normalised($0.identity) })
        let interaction = Set(candidates.filter { $0.population == .interaction }.map { Self.normalised($0.identity) })
        let counts = [decisions?.orphans(among: algebraic), interactionDecisions?.orphans(among: interaction)]
            .compactMap(\.self)
        return (
            counts.isEmpty ? nil : counts.reduce(0, +),
            evidence?.orphans(among: algebraic.union(interaction))
        )
    }
}
