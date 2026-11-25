//
//  MutantsRan.swift
//  SwiftStatsCore
//
//  What a snapshot's mutation results show the tests ran of each record,
//  for dead but tested (M7, design §8.2): the record's own mutants (those
//  placed on it) counted by verdict, its file's disposition, and whether
//  the run that tested its file had coverage off, through the file's run
//  (`mutationFile.run`), else, when the file names none, each mutant's own
//  run. With coverage on, SwiftMutator makes mutants only in code the
//  tests ran, so a mutant killed, survived or timed out shows a test
//  executed it; with coverage off it mutates code no test runs too, and
//  such a mutant reads as survived, so only a kill shows it. A record's
//  setting is its file's run's, else the one its mutants' runs share, and
//  unknown when they differ or it has none. Several records of one file
//  can be judged together (a production-dead function and the records
//  nested in it), their mutants taken as one record's. Paths are compared
//  in NFC, as the mapping compares them.
//

/// The mutants the tests ran, per record.
struct MutantsRan {
    /// What the mutation results show of one record.
    struct Facts {
        /// Its mutants counted; nil when it has none.
        let counts: MutationCounts?
        /// Of its survived and timed-out mutants, those from a run with
        /// coverage off, which don't show a test ran them.
        let unchecked: Int
        /// The coverage setting of the run that tested its file; nil when
        /// that isn't known: its file names no run and its mutants come
        /// from runs whose settings differ, or from none.
        let coverage: SignalItem.CoverageSetting?
        /// Its file's disposition; nil when the results don't name the file.
        let disposition: MutationFileDisposition?

        /// Its mutants a test ran: killed, survived and timed out, less
        /// the survived and timed-out ones of a run with coverage off.
        var ran: Int {
            guard let counts else {
                return 0
            }
            return counts.killed + counts.survived + counts.timedOut - unchecked
        }
    }

    /// Each record's mutants, by key.
    private let mutants: [String: [Mutant]]
    /// Each file, by NFC path.
    private let files: [NFCPath: MutationFile]
    /// Whether each run had coverage off, by ordinal.
    private let skipsCoverage: [Int: Bool]

    /// The mutants `report` shows ran.
    init(_ report: MutationReport) {
        mutants = Dictionary(grouping: report.mutants.filter { $0.place == .record }) { $0.owner ?? "" }
        files = Dictionary(report.files.map { (NFCPath($0.path), $0) }) { first, _ in first }
        skipsCoverage = Dictionary(report.runs.map { ($0.ordinal, $0.skipCoverage) }) { first, _ in first }
    }

    /// What the results show of the record keyed `key` in `path`: each
    /// mutant judged by its file's run, else by its own; a run the results
    /// don't list reads as coverage on.
    func facts(key: String, path: String) -> Facts {
        facts(keys: [key], path: path)
    }

    /// What the results show of the records keyed `keys`, all in `path`,
    /// taken together: their mutants judged as `facts(key:path:)` judges
    /// one record's.
    func facts(keys: [String], path: String) -> Facts {
        let held = keys.flatMap { mutants[$0] ?? [] }
        let file = files[NFCPath(path)]
        let skips = { (mutant: Mutant) in skipsCoverage[file?.run ?? mutant.run] ?? false }
        let unchecked = held.count { mutant in
            (mutant.verdict == .survived || mutant.verdict == .timedOut) && skips(mutant)
        }
        let settings = Set(held.map(skips))
        let skipped = file?.run.map { skipsCoverage[$0] ?? false } ?? (settings.count == 1 ? settings.first : nil)
        return Facts(
            counts: held.isEmpty ? nil : MutationCounts(held),
            unchecked: unchecked,
            coverage: skipped.map { $0 ? .disabled : .enabled },
            disposition: file?.disposition
        )
    }
}
