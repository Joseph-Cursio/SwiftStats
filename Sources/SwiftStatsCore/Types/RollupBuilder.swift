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
        let scopes = targets.sorted { $0.name < $1.name }
            .map { (RollupScope.module, $0.name, Set([$0.name]), $0.isTest) }
            + [("production", false), ("tests", true)].compactMap { name, isTest in
                let modules = Set(targets.filter { $0.isTest == isTest }.map(\.name))
                return modules.isEmpty ? nil : (RollupScope.project, name, modules, isTest)
            }
        return scopes.map { scope, name, modules, isTest in
            rollup(
                scope: scope,
                name: name,
                input: input.narrowed(to: modules),
                tests: TestSummaryBuilder.summary(of: modules, scope: scope, targets: targets, scan: input),
                isProduction: isTest == false
            )
        }
    }

    /// The roll-up of `input`, with its test summary; a production scope
    /// also counts law checks, and side effects and clones when they were
    /// collected.
    /// Suggestions count by file, and the project's production part also
    /// counts those placed in no scanned file.
    private static func rollup(
        scope: RollupScope,
        name: String,
        input: RollupInput,
        tests: TestSummary,
        isProduction: Bool
    ) -> Rollup {
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
            tests: tests,
            effects: isProduction && input.effectsCollected ? EffectRollup(records) : nil,
            laws: isProduction ? LawRollup(input.laws) : nil,
            properties: input.properties.flatMap { properties in
                PropertyRollup(properties.candidates, in: paths, countsUnplaced: scope == .project && isProduction)
            },
            clones: input.clones.flatMap { clones in
                isProduction ? CloneRollup(clones.report, linesByFile: clones.linesByFile, in: paths) : nil
            }
        )
    }

    /// How often each value occurs.
    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }
}
