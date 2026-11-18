//
//  RollupBuilder.swift
//  SwiftStatsCore
//
//  Summarises records per module and for the project (PRD §7.2). The
//  project is split into production and test modules, so test code doesn't
//  dilute the production figures.
//

/// Builds the roll-ups of a scan.
enum RollupBuilder {
    /// One roll-up per module, by name, then `production` and `tests` for
    /// the project when the package has modules of that kind.
    static func rollups(
        targets: [TargetSummary],
        records: [FunctionRecord],
        types: [TypeRecord],
        files: [FileRecord]
    ) -> [Rollup] {
        let scopes = targets.sorted { $0.name < $1.name }.map { (RollupScope.module, $0.name, Set([$0.name])) }
            + [("production", false), ("tests", true)].compactMap { name, isTest in
                let modules = Set(targets.filter { $0.isTest == isTest }.map(\.name))
                return modules.isEmpty ? nil : (RollupScope.project, name, modules)
            }
        return scopes.map { scope, name, modules in
            rollup(
                scope: scope,
                name: name,
                records: records.filter { modules.contains($0.module) },
                types: types.filter { modules.contains($0.module) },
                files: files.filter { modules.contains($0.module) }
            )
        }
    }

    /// The roll-up of these records, types and files.
    private static func rollup(
        scope: RollupScope,
        name: String,
        records: [FunctionRecord],
        types: [TypeRecord],
        files: [FileRecord]
    ) -> Rollup {
        let scores = records.compactMap(\.complexity)
        return Rollup(
            scope: scope,
            name: name,
            files: files.count,
            functions: counts(records.map(\.kind.rawValue)),
            documentedFunctions: records.filter(\.isDocumented).count,
            types: counts(types.map(\.kind.rawValue)),
            functionLength: Distribution(records.map(\.strippedLines)),
            parameterCount: Distribution(records.compactMap(\.parameterCount)),
            maxNesting: Distribution(scores.map(\.maxNesting)),
            cognitive: Distribution(scores.map(\.cognitive)),
            decisionCount: Distribution(scores.map(\.decisionCount)),
            swiftLintCompatible: Distribution(scores.filter(\.swiftLintScored).map(\.swiftLintCompatible)),
            typeBodyLength: Distribution(types.map(\.strippedLines)),
            typeMemberCount: Distribution(types.map(\.memberCount)),
            fileLength: Distribution(files.map(\.strippedLines))
        )
    }

    /// How often each value occurs.
    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }
}
