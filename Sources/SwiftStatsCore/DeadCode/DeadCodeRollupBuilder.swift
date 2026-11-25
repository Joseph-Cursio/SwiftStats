//
//  DeadCodeRollupBuilder.swift
//  SwiftStatsCore
//
//  Counts a dead-code report over each production module and the
//  production part (M7, design §5.4, §7, §10.3), and gives every roll-up's
//  line ratio its dead lines. It needs only the targets, the records and
//  the report, so a fresh scan and a scan that carries earlier dead-code
//  results build the same roll-ups. A covered record belongs to its
//  module, and to the production part when it is production code; an
//  unused declaration to its file's module. Test modules and the `tests`
//  part get no counts, since test-target entries are dropped. A line
//  ratio's dead lines are the `roots` run's in the production modules the
//  ratio measures against (`TestSummaryBuilder.ratioModules`).
//

/// Builds the dead-code part of a scan's roll-ups.
struct DeadCodeRollupBuilder {
    /// The scanned targets.
    private let targets: [TargetSummary]
    /// The test targets, by name.
    private let testModules: Set<String>
    /// The report.
    private let report: DeadCodeReport
    /// Each record, by key.
    private let records: [String: FunctionRecord]
    /// The `roots` run's unused production declarations.
    private let unused: [DeadCodeDeclaration]

    /// A builder of `report`'s roll-ups over `targets`, whose function
    /// records are `records`.
    init(targets: [TargetSummary], records: [FunctionRecord], report: DeadCodeReport) {
        self.targets = targets
        testModules = Set(targets.filter(\.isTest).map(\.name))
        self.report = report
        self.records = Dictionary(records.map { ($0.key, $0) }) { first, _ in first }
        unused = report.declarations.filter { $0.run == .roots && $0.isUnusedProduction }
    }

    /// `rollups` with each production scope's dead-code counts and every
    /// line ratio's dead lines.
    func rollups(_ rollups: [Rollup]) -> [Rollup] {
        rollups.map { rollup in
            let modules = RollupBuilder.modules(of: rollup, targets: targets)
            let measured = TestSummaryBuilder.ratioModules(scope: rollup.scope, modules: modules, targets: targets)
            let ratio = rollup.with(deadLines: report.deadLines(of: .roots, in: measured.production))
            guard modules.isDisjoint(with: testModules) else {
                return ratio
            }
            let isProject = rollup.scope == .project
            let held = { (record: FunctionRecord) in
                isProject ? record.role == .production : modules.contains(record.module)
            }
            return ratio.with(deadCode: DeadCodeRollup(
                records: covered(in: .roots, by: held),
                productionRecords: covered(in: .production, by: held),
                declarations: unused.filter { declaration in
                    declaration.module.map { modules.contains($0) } ?? false
                }
            ))
        }
    }

    /// How many records `run` covers that `held` holds.
    private func covered(in run: DeadCodeRun, by held: (FunctionRecord) -> Bool) -> Int {
        report.records.count { row in
            row.run == run && (records[row.key].map(held) ?? false)
        }
    }
}
