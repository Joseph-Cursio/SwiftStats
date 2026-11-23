//
//  MutationReport.swift
//  SwiftStatsCore
//
//  What the SwiftMutator collector's results hold, mapped onto the scan
//  (M6, design §3): when and how they were made, the tree they describe,
//  the runs that made them, the suspect tests, every mutant with where it
//  went, and the mutants counted per record, per attachment, over every
//  mutant, dropped by class and unmapped by reason. The counts follow from
//  the mutants, so a report is built from its mutants (as the store's rows
//  rebuild it) and a fresh, carried or merged one can't disagree with
//  them. Absent when the collector didn't run.
//

/// A snapshot's mutation results, mapped to records.
public struct MutationReport: Codable, Hashable, Sendable {
    /// When the results were collected: when the newest run's first
    /// session started, as SwiftMutator wrote it.
    public let collectedAt: String
    /// Whether every mutant the runs discovered has a result and the last
    /// session finished; when false, scores are left out above records.
    public let complete: Bool
    /// Whether the results list the mutants of code no test ran.
    public let listsNotCovered: Bool
    /// A full run, or a `--since` run merged with a base.
    public let mode: MutationMode
    /// The base snapshot of a `--since` merge; nil for a full run.
    public let base: MutationSource?
    /// Every Swift path of the tree the results describe, and each path
    /// deleted since the base, by path.
    public let files: [MutationFile]
    /// The runs the mutants refer to, by ordinal.
    public let runs: [MutationRunRecord]
    /// The tests SwiftMutator judged suspect, by run, then name, then file.
    public let suspectTests: [MutationSuspectTest]
    /// Every mutant, by path, line, column, operator and occurrence.
    public let mutants: [Mutant]
    /// Each production record holding a mutant, by key.
    public let records: [MutationRecord]
    /// Mutants attached to types and files, by what they attach to, then
    /// owner.
    public let attachments: [MutationAttachment]
    /// Every mutant, counted.
    public let everyMutant: MutationTotals
    /// The mutants dropped by design, by class.
    public let dropped: MutationDropped
    /// The unmapped mutants, by reason.
    public let unmapped: [String: Int]

    /// Why results whose `listsNotCovered` is false don't list code no
    /// test ran: no run, so a full run that found no code SwiftMutator
    /// could test, or else a SwiftMutator build that doesn't list it.
    var notListedCause: String {
        runs.isEmpty ? "the run found no code SwiftMutator could test" : "a SwiftMutator build before 13f96a46"
    }

    /// Creates a report. Fields are documented on their properties.
    public init(
        collectedAt: String,
        complete: Bool,
        listsNotCovered: Bool,
        mode: MutationMode,
        base: MutationSource?,
        files: [MutationFile],
        runs: [MutationRunRecord],
        suspectTests: [MutationSuspectTest],
        mutants: [Mutant],
        records: [MutationRecord],
        attachments: [MutationAttachment],
        everyMutant: MutationTotals,
        dropped: MutationDropped,
        unmapped: [String: Int]
    ) {
        self.collectedAt = collectedAt
        self.complete = complete
        self.listsNotCovered = listsNotCovered
        self.mode = mode
        self.base = base
        self.files = files
        self.runs = runs
        self.suspectTests = suspectTests
        self.mutants = mutants
        self.records = records
        self.attachments = attachments
        self.everyMutant = everyMutant
        self.dropped = dropped
        self.unmapped = unmapped
    }

    /// The report of `mutants`, whose records, attachments and counts it
    /// works out; files, runs, suspect tests and mutants are put in the
    /// report's order.
    init(
        collectedAt: String,
        complete: Bool,
        listsNotCovered: Bool,
        mode: MutationMode,
        base: MutationSource?,
        files: [MutationFile],
        runs: [MutationRunRecord],
        suspectTests: [MutationSuspectTest],
        mutants: [Mutant]
    ) {
        let sorted = mutants.sorted { $0.key < $1.key }
        let unmappedMutants = sorted.filter { $0.place == .unmapped }
        self.init(
            collectedAt: collectedAt,
            complete: complete,
            listsNotCovered: listsNotCovered,
            mode: mode,
            base: base,
            files: files.sorted { $0.path < $1.path },
            runs: runs.sorted { $0.ordinal < $1.ordinal },
            suspectTests: suspectTests.sorted(by: MutationSuspectTest.reportOrder),
            mutants: sorted,
            records: Self.records(of: sorted),
            attachments: Self.attachments(of: sorted),
            everyMutant: MutationTotals(
                counts: MutationCounts(sorted),
                dropped: sorted.count { $0.place == .dropped },
                unmapped: unmappedMutants.count
            ),
            dropped: MutationDropped(sorted),
            unmapped: Dictionary(grouping: unmappedMutants) { $0.reason ?? "" }.mapValues(\.count)
        )
    }

    /// The records `mutants` were placed on, by key, each with its counts
    /// and the distinct tests named failing for its kills.
    private static func records(of mutants: [Mutant]) -> [MutationRecord] {
        let byKey = Dictionary(grouping: mutants.filter { $0.place == .record }) { $0.owner ?? "" }
        return byKey.keys.sorted().map { key in
            let held = byKey[key] ?? []
            let killing = Set(held.filter { $0.verdict == .killed }.flatMap(\.killedBy))
            return MutationRecord(key: key, counts: MutationCounts(held), killingTests: killing.sorted())
        }
    }

    /// The types and files `mutants` were attached to, by what they attach
    /// to, then owner, each with its counts.
    private static func attachments(of mutants: [Mutant]) -> [MutationAttachment] {
        var held: [FindingTarget: [String: [Mutant]]] = [:]
        for mutant in mutants {
            switch mutant.place {
            case .type:
                held[.type, default: [:]][mutant.owner ?? "", default: []].append(mutant)

            case .file:
                held[.file, default: [:]][mutant.owner ?? "", default: []].append(mutant)

            case .record, .unmapped, .dropped:
                continue
            }
        }
        return held.keys.sorted { $0.rawValue < $1.rawValue }.flatMap { target in
            let owners = held[target] ?? [:]
            return owners.keys.sorted().map { owner in
                MutationAttachment(owner: owner, attachedTo: target, counts: MutationCounts(owners[owner] ?? []))
            }
        }
    }
}
