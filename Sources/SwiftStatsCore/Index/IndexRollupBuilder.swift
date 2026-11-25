//
//  IndexRollupBuilder.swift
//  SwiftStatsCore
//
//  Counts an index report's USRs and coupling over each module and each
//  part of the project (M7, design §3.4, §4.2, §4.3): every scope, test
//  modules and the `tests` part included, since the index covers tests
//  too. It needs only the targets, the records and the report, so a fresh
//  scan and a scan that carries earlier index results build the same
//  roll-ups. A record belongs to its module, a type to its module and an
//  edge to the module it starts at; a part holds the records and edges of
//  its targets. The production part counts every USR type cycle, since
//  cycles are over production types only, and the `tests` part none.
//

/// Builds the index part of a scan's roll-ups.
struct IndexRollupBuilder {
    /// The test targets, by name.
    private let testModules: Set<String>
    /// Each module's records' reasons, nil for a record with a USR.
    private let reasons: [String: [USRReason?]]
    /// Each module's types' cycle numbers, one per type in a cycle.
    private let cycles: [String: [Int]]
    /// How many module edges start at each module.
    private let edges: [String: Int]

    /// A builder of `report`'s roll-ups over `targets`, whose function
    /// records are `records`.
    init(targets: [TargetSummary], records: [FunctionRecord], report: IndexReport) {
        let byKey = Dictionary(report.records.map { ($0.key, $0) }) { first, _ in first }
        testModules = Set(targets.filter(\.isTest).map(\.name))
        reasons = Dictionary(grouping: records, by: \.module).mapValues { held in
            held.map { record in
                byKey[record.key].map { $0.usr == nil ? $0.reason ?? .unexplained : nil } ?? .unexplained
            }
        }
        cycles = Dictionary(grouping: report.types.filter { $0.cycle != nil }, by: \.module)
            .mapValues { $0.compactMap(\.cycle) }
        edges = Dictionary(grouping: report.moduleEdges, by: \.fromModule).mapValues(\.count)
    }

    /// `rollups` with the index counts of each module and of each part of
    /// the project.
    func rollups(_ rollups: [Rollup]) -> [Rollup] {
        rollups.map { rollup in
            switch rollup.scope {
            case .module:
                return rollup.with(index: IndexRollup(
                    reasons[rollup.name, default: []],
                    cycles: cycles[rollup.name, default: []],
                    moduleEdges: edges[rollup.name, default: 0]
                ))

            case .project:
                let isTest = rollup.name == "tests"
                let held = reasons.filter { testModules.contains($0.key) == isTest }
                    .sorted { $0.key < $1.key }
                    .flatMap(\.value)
                return rollup.with(index: IndexRollup(
                    held,
                    cycles: isTest ? [] : cycles.values.flatMap(\.self),
                    moduleEdges: edges.filter { testModules.contains($0.key) == isTest }.values.reduce(0, +)
                ))
            }
        }
    }
}
