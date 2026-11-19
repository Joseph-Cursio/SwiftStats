//
//  MetricDirection.swift
//  SwiftStatsCore
//
//  Which way is better for each metric (PRD §6.6): lower for sizes,
//  complexity, nesting, parameters and findings; higher for tests,
//  assertions, documentation and the test line ratio; neutral for counts.
//

/// Whether a metric going up is good, bad or neither.
public enum MetricDirection: String, Codable, Hashable, Sendable {
    /// Higher is better.
    case higherIsBetter = "higher-is-better"
    /// Lower is better.
    case lowerIsBetter = "lower-is-better"
    /// Neither.
    case neutral

    /// Path parts of a distribution field: the field and its statistic.
    private static let distributionDepth = 2
    /// Distribution fields that measure size rather than count.
    private static let sizeFields: Set<String> = ["total", "min", "median", "p90", "max"]
    /// Roll-up fields whose distribution sizes are better lower.
    private static let lowerDistributions: Set<String> = [
        "functionLength", "parameterCount", "maxNesting", "cognitive", "decisionCount",
        "swiftLintCompatible", "typeBodyLength", "typeMemberCount", "fileLength"
    ]
    /// Paths, or path prefixes ending in a dot, that are better lower.
    private static let lowerPaths = [
        "findings.", "findingKinds.", "api.overExposed", "tests.xctestWithoutAssertions",
        "tests.swiftTestingWithoutAssertions", "tests.parameterizedUnknownCases",
        "strippedLines", "parameterCount", "cognitive", "decisionCount", "swiftLintCompatible", "maxNesting"
    ]
    /// Paths, or path prefixes ending in a dot, that are better higher.
    private static let higherPaths = [
        "tests.tests.", "tests.parameterizedCases", "tests.lineRatio.testLines", "tests.lineRatio.testLinesByKind.",
        "documentedFunctions",
        "api.documentedPublicDeclarations"
    ]

    /// The direction of the metric at `path`, a roll-up path or a function metric.
    public static func of(_ path: String) -> Self {
        let parts = path.split(separator: ".").map(String.init)
        if parts.count == distributionDepth, lowerDistributions.contains(parts[0]) {
            return sizeFields.contains(parts[1]) ? .lowerIsBetter : .neutral
        }
        if path.hasPrefix("tests.assertionsPerTest.") {
            return sizeFields.contains(parts.last ?? "") ? .higherIsBetter : .neutral
        }
        if lowerPaths.contains(where: { matches(path, $0) }) {
            return .lowerIsBetter
        }
        if higherPaths.contains(where: { matches(path, $0) }) {
            return .higherIsBetter
        }
        return .neutral
    }

    /// Whether `path` is `pattern`, or starts with it when it ends in a dot.
    private static func matches(_ path: String, _ pattern: String) -> Bool {
        pattern.hasSuffix(".") ? path.hasPrefix(pattern) : path == pattern
    }
}
