//
//  MutationJudge.swift
//  SwiftStatsCore
//
//  What M6's per-function signals read from a snapshot's mutation results
//  (design §4, §7): each production record's mutants counted by verdict,
//  its state (from those counts and its file's disposition, paths compared
//  in NFC as the mapping compares them), its figures, the mutants its
//  tests ran and didn't check, the suspect tests behind its suspect-only
//  kills, its unkilled mutants, and its line coverage. A function has
//  coverage data when its line tally maps at least one line; a snapshot
//  read without coverage (best property-test target needs none) gives
//  none. For clone copies (uneven clone testing, mutation part) it also
//  indexes each file's mapped mutants (placed on a record, a type or the
//  file) by anchor, so a copy's mutants are those anchored in its range.
//

import Foundation

/// Reads a snapshot's mutation results per production function.
struct MutationJudge {
    /// The verdicts of mutants the tests ran and didn't check.
    private static let unchecked: Set<MutationVerdict> = [.survived, .timedOut]
    /// The verdicts of mutants the tests didn't kill.
    private static let notKilled: Set<MutationVerdict> = [.survived, .timedOut, .noCoverage, .notCovered]
    /// The killing tests an item names.
    static let namedKillingTests = 5
    /// The position before every other, standing for a missing anchor,
    /// which the anchor index never holds.
    private static let origin = SourcePosition(line: 0, column: 0)
    /// What a binary search divides its span by.
    private static let halves = 2

    /// The production function rows outside generated files.
    let functions: ProductionFunctions
    /// Each record's counts, by key.
    private let counts: [String: MutationCounts]
    /// Each record's killing tests, by key.
    private let killingTests: [String: [String]]
    /// Each record's mutants, by key, in the report's order.
    private let mutants: [String: [Mutant]]
    /// Each file's disposition, by NFC path.
    private let dispositions: [NFCPath: MutationFileDisposition]
    /// Each record's coverage, by key.
    private let coverage: [String: CoverageRecord]
    /// The suspect tests, by run, then name.
    private let suspects: [Int: [String: [MutationSuspectTest]]]
    /// Each file's mapped mutants, by NFC path, sorted by anchor, then key.
    private let anchored: [NFCPath: [Mutant]]

    /// A judge of `snapshot`'s `mutation` results with its `coverage` (none
    /// when nil).
    init(_ snapshot: StoredSnapshot, mutation: MutationReport, coverage: CoverageReport?) {
        functions = ProductionFunctions(snapshot)
        counts = Dictionary(mutation.records.map { ($0.key, $0.counts) }) { first, _ in first }
        killingTests = Dictionary(mutation.records.map { ($0.key, $0.killingTests) }) { first, _ in first }
        mutants = Dictionary(grouping: mutation.mutants.filter { $0.place == .record }) { $0.owner ?? "" }
        dispositions = Dictionary(
            mutation.files.map { (NFCPath($0.path), $0.disposition) }
        ) { first, _ in first }
        self.coverage = Dictionary((coverage?.records ?? []).map { ($0.key, $0) }) { first, _ in first }
        suspects = Dictionary(grouping: mutation.suspectTests, by: \.run).mapValues { tests in
            Dictionary(grouping: tests, by: \.name)
        }
        anchored = Self.anchorIndex(mutation.mutants)
    }

    /// `mutants` placed on a record, a type or a file with an anchor, by
    /// NFC path, each file's sorted by anchor, then key.
    private static func anchorIndex(_ mutants: [Mutant]) -> [NFCPath: [Mutant]] {
        let mapped = mutants.filter { mutant in
            mutant.anchor != nil && (mutant.place == .record || mutant.place == .type || mutant.place == .file)
        }
        return Dictionary(grouping: mapped) { NFCPath($0.path) }.mapValues { held in
            held.sorted { left, right in
                let (leftAnchor, rightAnchor) = (left.anchor ?? Self.origin, right.anchor ?? Self.origin)
                return leftAnchor == rightAnchor ? left.key < right.key : leftAnchor < rightAnchor
            }
        }
    }

    /// The mapped mutants (placed on a record, a type or the file) of
    /// `file` whose anchor lies in `range`, ends included, by anchor, then
    /// key; paths compared in NFC.
    func mutants(in file: String, range: SourceSpan) -> [Mutant] {
        let held = anchored[NFCPath(file)] ?? []
        var low = 0
        var high = held.count
        while low < high {
            let middle = (low + high) / Self.halves
            if (held[middle].anchor ?? Self.origin) < range.start {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return Array(held[low...].prefix { ($0.anchor ?? Self.origin) <= range.end })
    }

    /// The disposition of `file`'s results; nil when the results don't name
    /// it. Paths compared in NFC.
    func disposition(of file: String) -> MutationFileDisposition? {
        dispositions[NFCPath(file)]
    }

    /// `row`'s mutants counted; nil when it has none.
    func counts(of row: FunctionRow) -> MutationCounts? {
        counts[row.key]
    }

    /// The mutants of the record keyed `key` counted; nil when it has none.
    func counts(key: String) -> MutationCounts? {
        counts[key]
    }

    /// The mutants of the record keyed `key` its tests didn't kill
    /// (survived, timed out, no coverage, not covered), in the report's
    /// order.
    func unkilled(key: String) -> [UncheckedMutant] {
        (mutants[key] ?? []).filter { Self.notKilled.contains($0.verdict) }.map(UncheckedMutant.init)
    }

    /// `row`'s mutation state.
    func state(of row: FunctionRow) -> MutationFunctionState {
        MutationFunctionState(
            counts: counts[row.key],
            disposition: dispositions[NFCPath(row.file)]
        )
    }

    /// `row`'s line coverage; nil when it has no coverage data (no line
    /// tally, or one mapping no line).
    func lines(of row: FunctionRow) -> CoverageTally? {
        guard let lines = coverage[row.key]?.lines, lines.total > 0 else {
            return nil
        }
        return lines
    }

    /// `row`'s coverage payload: its lines and regions.
    func coveragePayload(of row: FunctionRow) -> SignalItem.Coverage {
        let record = coverage[row.key]
        return SignalItem.Coverage(lines: record?.lines, regions: record?.regions)
    }

    /// `row`'s mutation payload, from its `counts`.
    func payload(of row: FunctionRow, counts: MutationCounts) -> SignalItem.Mutation {
        let figures = MutationFigures(counts)
        let held = mutants[row.key] ?? []
        let tests = killingTests[row.key] ?? []
        return SignalItem.Mutation(
            counts: counts,
            score: figures.score,
            functionScore: figures.functionScore,
            killingTests: tests.count,
            firstKillingTests: Array(tests.prefix(Self.namedKillingTests)),
            survivors: held.filter { Self.unchecked.contains($0.verdict) }.map(UncheckedMutant.init),
            suspects: suspects(behind: held)
        )
    }

    /// The suspect tests the suspect-only kills among `held` name, each
    /// judged by the run that made the kill, with why and, for reach, in
    /// how many of the files with kills it failed, each distinct entry
    /// once; by name, then why, then those figures (none first).
    private func suspects(behind held: [Mutant]) -> [SignalItem.Suspect] {
        var found: Set<SignalItem.Suspect> = []
        for mutant in held where mutant.suspectOnly?.value == true {
            for name in mutant.killedBy {
                for test in suspects[mutant.run]?[name] ?? [] {
                    found.insert(SignalItem.Suspect(
                        name: name,
                        why: test.why.rawValue,
                        files: test.files,
                        filesWithKills: test.filesWithKills
                    ))
                }
            }
        }
        return found.sorted { left, right in
            (left.name, left.why, left.files ?? -1, left.filesWithKills ?? -1)
                < (right.name, right.why, right.files ?? -1, right.filesWithKills ?? -1)
        }
    }
}
