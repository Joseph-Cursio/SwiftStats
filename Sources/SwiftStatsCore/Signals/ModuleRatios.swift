//
//  ModuleRatios.swift
//  SwiftStatsCore
//
//  The test-to-code line ratios genuinely under-tested judges modules by
//  (M6, design §7.2, U8; PRD §7.8), read from the stored roll-ups: each
//  production module's test lines (of the tests whose test target depends
//  on it directly) and production lines, and the project's. A module's
//  test code is low when no test line is measured against it, when its
//  ratio lies below the project's (compared by cross-multiplying), or,
//  when the configuration sets `signals.genuinely-under-tested.ratio`,
//  when it lies below that. The production modules are those whose
//  roll-ups hold mutation results, which every production module's does.
//

/// The production modules' and the project's line ratios.
struct ModuleRatios {
    /// Why a module's test code is low, or that it isn't.
    enum Standing: Hashable, Sendable {
        /// No test line is measured against it.
        case noTestCode
        /// Its ratio lies below the project's.
        case belowProject
        /// Its ratio lies below the configured ratio, not the project's.
        case belowRatio
        /// Its test code isn't low.
        case notLow

        /// Whether its test code is low.
        var isLow: Bool {
            self != .notLow
        }
    }

    /// The roll-up metric of test lines.
    private static let testLinesMetric = "tests.lineRatio.testLines"
    /// The roll-up metric of production lines.
    private static let productionLinesMetric = "tests.lineRatio.productionLines"
    /// A roll-up metric every production module's mutation results hold.
    private static let mutationMetric = "mutation.killed"
    /// The project roll-up of production code.
    private static let productionPart = "production"

    /// The production modules, sorted.
    let modules: [String]
    /// The project's lines; nil when its roll-up holds none.
    let project: SignalItem.RatioLines?
    /// Each module's lines, by name; absent when its roll-up holds none.
    private let lines: [String: SignalItem.RatioLines]
    /// The configured ratio, test lines per production line, below which a
    /// module's test code is low; nil when unset.
    private let ratio: Double?

    /// The ratios of `snapshot`, with `ratio` the configured one (nil when
    /// unset).
    init(_ snapshot: StoredSnapshot, ratio: Double?) {
        var tests: [String: Int] = [:]
        var codeLines: [String: Int] = [:]
        var production: Set<String> = []
        var projectTests: Int?
        var projectProduction: Int?
        for row in snapshot.rollups {
            switch (row.scope, row.metric) {
            case (.module, Self.mutationMetric):
                production.insert(row.name)

            case (.module, Self.testLinesMetric):
                tests[row.name] = Int(row.value)

            case (.module, Self.productionLinesMetric):
                codeLines[row.name] = Int(row.value)

            case (.project, Self.testLinesMetric) where row.name == Self.productionPart:
                projectTests = Int(row.value)

            case (.project, Self.productionLinesMetric) where row.name == Self.productionPart:
                projectProduction = Int(row.value)

            default:
                continue
            }
        }
        var measured: [String: SignalItem.RatioLines] = [:]
        for (name, testLines) in tests {
            if let productionLines = codeLines[name] {
                measured[name] = SignalItem.RatioLines(testLines: testLines, productionLines: productionLines)
            }
        }
        modules = production.sorted()
        lines = measured
        self.ratio = ratio
        project = projectTests.flatMap { testLines in
            projectProduction.map { SignalItem.RatioLines(testLines: testLines, productionLines: $0) }
        }
    }

    /// The ratio payload of `module`.
    func payload(_ module: String) -> SignalItem.Ratio {
        SignalItem.Ratio(module: module, moduleLines: lines[module], projectLines: project)
    }

    /// Where `module`'s test code stands, the first that applies: no test
    /// line measured against it (or none recorded), below the project's
    /// ratio, below the configured ratio, else not low.
    func standing(_ module: String) -> Standing {
        guard let own = lines[module], own.testLines > 0 else {
            return .noTestCode
        }
        if let project, own.testLines * project.productionLines < project.testLines * own.productionLines {
            return .belowProject
        }
        if let ratio, Double(own.testLines) < ratio * Double(own.productionLines) {
            return .belowRatio
        }
        return .notLow
    }
}
