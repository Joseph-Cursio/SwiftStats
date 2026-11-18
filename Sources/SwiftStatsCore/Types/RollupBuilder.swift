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
    static func rollups(targets: [TargetSummary], input: RollupInput) -> [Rollup] {
        let scopes = targets.sorted { $0.name < $1.name }.map { (RollupScope.module, $0.name, Set([$0.name])) }
            + [("production", false), ("tests", true)].compactMap { name, isTest in
                let modules = Set(targets.filter { $0.isTest == isTest }.map(\.name))
                return modules.isEmpty ? nil : (RollupScope.project, name, modules)
            }
        return scopes.map { scope, name, modules in
            rollup(
                scope: scope,
                name: name,
                input: input.narrowed(to: modules),
                tests: TestSummaryBuilder.summary(of: modules, scope: scope, targets: targets, scan: input)
            )
        }
    }

    /// The roll-up of `input`, with its test summary.
    private static func rollup(scope: RollupScope, name: String, input: RollupInput, tests: TestSummary) -> Rollup {
        let records = input.records
        let types = input.types
        let files = input.files
        let scores = records.compactMap(\.complexity)
        let paths = Set(files.map(\.path))
        return Rollup(
            scope: scope,
            name: name,
            files: files.count,
            functions: counts(records.map(\.kind.rawValue)),
            documentedFunctions: records.filter(\.isDocumented).count,
            asyncFunctions: records.filter(\.isAsync).count,
            types: counts(types.map(\.kind.rawValue)),
            functionLength: Distribution(records.map(\.strippedLines)),
            parameterCount: Distribution(records.compactMap(\.parameterCount)),
            maxNesting: Distribution(scores.map(\.maxNesting)),
            cognitive: Distribution(scores.map(\.cognitive)),
            decisionCount: Distribution(scores.map(\.decisionCount)),
            swiftLintCompatible: Distribution(scores.filter(\.swiftLintScored).map(\.swiftLintCompatible)),
            typeBodyLength: Distribution(types.map(\.strippedLines)),
            typeMemberCount: Distribution(types.map(\.memberCount)),
            fileLength: Distribution(files.map(\.strippedLines)),
            findings: input.findings.byRule(in: paths),
            findingKinds: input.findings.byKind(in: paths),
            api: APISurface(input.declarations, overExposed: input.findings.overExposed(in: paths)),
            tests: tests
        )
    }

    /// How often each value occurs.
    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }
}
