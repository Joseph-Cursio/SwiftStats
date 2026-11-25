//
//  TypeCheckRollupBuilder.swift
//  SwiftStatsCore
//
//  Rolls a build report's type-check figures up over each module and each
//  part of the project (M7, design §6.2, §6.4): every scope, test modules
//  and the `tests` part included, since the T1 build times every role. A
//  record belongs to its module, and a part holds the records of its
//  targets. The maxima and the records timed take every record, those
//  nested in a body included, and only records (a type's or a file's
//  entries aren't a record's); the totals, which leave out the records
//  nested in a body and add the types' and files' entries, come from
//  `TypeCheckTotals`, since the report's rounded per-record figures can't
//  give them exactly.
//

/// Builds the type-check part of a scan's roll-ups.
struct TypeCheckRollupBuilder {
    /// The test targets, by name.
    private let testModules: Set<String>
    /// Each module's records' figures.
    private let timings: [String: [BuildRecordTiming]]
    /// Each scope's total.
    private let totals: TypeCheckTotals

    /// A builder of `report`'s roll-ups over `targets`, whose function
    /// records are `records`, with `totals` as each scope's total.
    init(targets: [TargetSummary], records: [FunctionRecord], report: BuildReport, totals: TypeCheckTotals) {
        let modules = Dictionary(records.map { ($0.key, $0.module) }) { first, _ in first }
        testModules = Set(targets.filter(\.isTest).map(\.name))
        timings = Dictionary(grouping: report.records.filter { modules[$0.key] != nil }) { modules[$0.key] ?? "" }
        self.totals = totals
    }

    /// `rollups` with the type-check figures of each module and of each
    /// part of the project.
    func rollups(_ rollups: [Rollup]) -> [Rollup] {
        rollups.map { rollup in
            let held: [BuildRecordTiming]
            switch rollup.scope {
            case .module:
                held = timings[rollup.name, default: []]

            case .project:
                let isTest = rollup.name == "tests"
                held = timings.filter { testModules.contains($0.key) == isTest }.flatMap(\.value)
            }
            let total = totals.total(rollup.scope, rollup.name)
            return rollup.with(typecheck: TypeCheckRollup(total: total, timings: held))
        }
    }
}
