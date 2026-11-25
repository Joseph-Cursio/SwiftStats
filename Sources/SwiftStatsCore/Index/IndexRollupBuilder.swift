//
//  IndexRollupBuilder.swift
//  SwiftStatsCore
//
//  Counts an index report's USRs over each module and each part of the
//  project (M7, design §3.4): every scope, test modules and the `tests`
//  part included, since the index covers tests too. It needs only the
//  targets, the records and the report, so a fresh scan and a scan that
//  carries earlier index results build the same roll-ups. A record
//  belongs to its module; a part holds the records of its targets.
//

/// Builds the USR part of a scan's roll-ups.
struct IndexRollupBuilder {
    /// The test targets, by name.
    private let testModules: Set<String>
    /// Each module's records' reasons, nil for a record with a USR.
    private let reasons: [String: [USRReason?]]

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
    }

    /// `rollups` with the USR counts of each module and of each part of
    /// the project.
    func rollups(_ rollups: [Rollup]) -> [Rollup] {
        rollups.map { rollup in
            switch rollup.scope {
            case .module:
                return rollup.with(index: IndexRollup(reasons[rollup.name, default: []]))

            case .project:
                let isTest = rollup.name == "tests"
                let held = reasons.filter { testModules.contains($0.key) == isTest }
                    .sorted { $0.key < $1.key }
                    .flatMap(\.value)
                return rollup.with(index: IndexRollup(held))
            }
        }
    }
}
