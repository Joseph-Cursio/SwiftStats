//
//  MutationRollupBuilder.swift
//  SwiftStatsCore
//
//  Sums a mutation report over each production module and the project's
//  production part (M6, design §4). It needs only the targets, the
//  records, the files and the report, no declarations, so a fresh scan, a
//  carried result and a merged one build the same roll-ups. A record's
//  mutants belong to its module, a type's attachment to the module its
//  owner names, a file's to the target listing the file; every mapped
//  mutant counts, a generated record's too, while only production
//  functions outside generated files are counted by state. A function's
//  state comes from its record's counts and its file's disposition, paths
//  compared in NFC as the mapping compares them.
//

import Foundation

/// Builds the mutation part of a scan's roll-ups.
struct MutationRollupBuilder {
    /// The separator between a type owner's module and its type path.
    private static let moduleSeparator = "::"

    /// The production modules, by name.
    private let modules: Set<String>
    /// Each module's mapped mutants.
    private let mutants: [String: [Mutant]]
    /// Each module's production functions outside generated files, by key,
    /// with their states.
    private let functions: [String: [String: MutationFunctionState]]
    /// The report summed.
    private let report: MutationReport

    /// A builder of `report`'s roll-ups over `targets`, whose function
    /// records are `records` and files `files`.
    init(targets: [TargetSummary], records: [FunctionRecord], files: [FileRecord], report: MutationReport) {
        let production = Set(targets.filter { $0.isTest == false }.map(\.name))
        modules = production
        let fileModules = Dictionary(
            targets.flatMap { target in target.files.map { ($0, target.name) } }
        ) { first, _ in first }
        let recordModules = Dictionary(records.map { ($0.key, $0.module) }) { first, _ in first }
        var byModule: [String: [Mutant]] = [:]
        for mutant in report.mutants {
            if let module = Self.module(of: mutant, recordModules: recordModules, fileModules: fileModules) {
                byModule[module, default: []].append(mutant)
            }
        }
        mutants = byModule
        functions = Self.states(
            of: records.filter { production.contains($0.module) && $0.role == .production },
            generated: Set(files.filter(\.generated).map(\.path)),
            report: report
        )
        self.report = report
    }

    /// The module `mutant` belongs to: its record's, its type owner's, or
    /// the target listing its file; nil when unmapped or dropped.
    private static func module(
        of mutant: Mutant,
        recordModules: [String: String],
        fileModules: [String: String]
    ) -> String? {
        guard let owner = mutant.owner else {
            return nil
        }
        switch mutant.place {
        case .record:
            return recordModules[owner]

        case .type:
            return owner.range(of: moduleSeparator).map { String(owner[..<$0.lowerBound]) }

        case .file:
            return fileModules[owner]

        case .unmapped, .dropped:
            return nil
        }
    }

    /// The state of each of `records` outside the `generated` files, by
    /// module, then key, from `report`'s record counts and file
    /// dispositions.
    private static func states(
        of records: [FunctionRecord],
        generated: Set<String>,
        report: MutationReport
    ) -> [String: [String: MutationFunctionState]] {
        let counts = Dictionary(report.records.map { ($0.key, $0.counts) }) { first, _ in first }
        let dispositions = Dictionary(
            report.files.map { (NFCPath($0.path), $0.disposition) }
        ) { first, _ in first }
        var states: [String: [String: MutationFunctionState]] = [:]
        for record in records where generated.contains(record.file) == false {
            states[record.module, default: [:]][record.key] = MutationFunctionState(
                counts: counts[record.key],
                disposition: dispositions[NFCPath(record.file)]
            )
        }
        return states
    }

    /// `rollups` with the mutation results of each production module and
    /// of the project's production part; test modules and the `tests` part
    /// as they were.
    func rollups(_ rollups: [Rollup]) -> [Rollup] {
        rollups.map { rollup in
            switch rollup.scope {
            case .module where modules.contains(rollup.name):
                rollup.with(mutation: self.rollup(of: [rollup.name], isProject: false))

            case .project where rollup.name == "production":
                rollup.with(mutation: self.rollup(of: modules, isProject: true))

            case .module, .project:
                rollup
            }
        }
    }

    /// The mutation results of `names`' modules; the project's part also
    /// counts the unmapped and dropped mutants.
    func rollup(of names: Set<String>, isProject: Bool) -> MutationRollup {
        let held = names.sorted().flatMap { mutants[$0] ?? [] }
        let counts = MutationCounts(held)
        let score = MutationFigures(counts).score
        return MutationRollup(
            counts: counts,
            score: report.complete ? score : score.withoutPercent(),
            carried: held.count(where: \.carried),
            functions: MutationRollup.Functions(names.sorted().flatMap { (functions[$0] ?? [:]).values }),
            unmapped: isProject ? report.everyMutant.unmapped : nil,
            dropped: isProject ? report.everyMutant.dropped : nil
        )
    }
}
