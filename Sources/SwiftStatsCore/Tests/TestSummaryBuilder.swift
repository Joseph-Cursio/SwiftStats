//
//  TestSummaryBuilder.swift
//  SwiftStatsCore
//
//  Counts a roll-up's tests and the lines behind its test-to-code ratio
//  (PRD §7.8).
//

/// Builds test summaries.
enum TestSummaryBuilder {
    /// The summary of the tests in `modules`, with the line ratio measured
    /// as `LineRatio` describes for a roll-up of those modules.
    static func summary(
        of modules: Set<String>,
        scope: RollupScope,
        targets: [TargetSummary],
        scan: RollupInput
    ) -> TestSummary {
        let tests = scan.tests.filter { modules.contains($0.module) }
        let counted = tests.filter { $0.generated == false }
        let parameterized = counted.filter { $0.kind == .parameterized }
        return TestSummary(
            tests: counted.reduce(into: [:]) { counts, test in
                counts[test.framework.rawValue, default: [:]][test.kind.rawValue, default: 0] += 1
            },
            generatedTests: tests.count - counted.count,
            helpers: scan.records.filter { modules.contains($0.module) && $0.role == .helper }.count,
            parameterizedCases: parameterized.compactMap(\.cases).reduce(0) { total, cases in
                // Saturates rather than trapping on absurd literal ranges.
                let (sum, overflow) = total.addingReportingOverflow(cases)
                return overflow ? Int.max : sum
            },
            parameterizedUnknownCases: parameterized.filter { $0.cases == nil }.count,
            assertionsPerTest: Distribution(counted.map(\.assertions)),
            xctestWithoutAssertions: counted.filter { $0.framework == .xctest && $0.assertions == 0 }.count,
            swiftTestingWithoutAssertions: missingAssertions(in: counted, findings: scan.findings),
            lineRatio: lineRatio(scope: scope, modules: modules, targets: targets, scan: scan)
        )
    }

    /// Swift Testing tests among `tests` that `testMissingAssertion` names.
    private static func missingAssertions(in tests: [TestRecord], findings: FindingTally) -> Int? {
        guard findings.tools.contains(SwiftProjectLintAdapter.name) else {
            return nil
        }
        let keys = Set(tests.filter { $0.framework == .swiftTesting }.map(\.key))
        let named = findings.findings
            .filter { $0.tool == SwiftProjectLintAdapter.name && $0.rule == "testMissingAssertion" }
            .compactMap { $0.locations.first?.owner }
        return Set(named).intersection(keys).count
    }

    /// The modules the line ratio of a roll-up of `modules` at `scope`
    /// measures, as `LineRatio` describes: the test modules whose tests it
    /// counts and the production modules whose files it measures against.
    static func ratioModules(
        scope: RollupScope,
        modules: Set<String>,
        targets: [TargetSummary]
    ) -> (testing: Set<String>, production: Set<String>) {
        let testModules = Set(targets.filter(\.isTest).map(\.name))
        let productionModules = Set(targets.filter { $0.isTest == false }.map(\.name))
        switch scope {
        case .project:
            return (testModules, productionModules)

        case .module where modules.isSubset(of: testModules):
            let production = Set(targets.filter { modules.contains($0.name) }.flatMap(\.dependencies))
                .intersection(productionModules)
            return (modules, production)

        case .module:
            let dependents = targets.filter { target in
                target.isTest && target.dependencies.contains { modules.contains($0) }
            }
            return (Set(dependents.map(\.name)), modules)
        }
    }

    /// The line ratio's counts for a roll-up of `modules` at `scope`.
    private static func lineRatio(
        scope: RollupScope,
        modules: Set<String>,
        targets: [TargetSummary],
        scan: RollupInput
    ) -> LineRatio {
        let (testing, production) = ratioModules(scope: scope, modules: modules, targets: targets)
        let tests = scan.tests.filter { testing.contains($0.module) && $0.generated == false }
        let lines = Dictionary(scan.records.map { ($0.key, $0.strippedLines) }) { first, _ in first }
        return LineRatio(
            testLines: tests.compactMap { lines[$0.key] }.reduce(0, +),
            testLinesByKind: tests.reduce(into: [:]) { counts, test in
                counts[test.kind.rawValue, default: 0] += lines[test.key] ?? 0
            },
            productionLines: scan.files.filter { production.contains($0.module) }.map(\.strippedLines).reduce(0, +),
            deadCodeExcluded: false,
            deadLines: nil
        )
    }
}
