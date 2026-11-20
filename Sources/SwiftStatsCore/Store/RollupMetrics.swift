//
//  RollupMetrics.swift
//  SwiftStatsCore
//
//  Each number in a roll-up as a named metric (PRD §9): its JSON path, such
//  as `cognitive.p90` or `findings.swiftlint.line_length`, and the collector
//  it comes from. A roll-up field added later needs no store migration.
//

import Foundation

/// Flattens roll-ups into named numbers.
enum RollupMetrics {
    /// One number in a roll-up.
    struct Metric: Hashable {
        /// Its path, keys joined with dots.
        let path: String
        /// The collector it comes from.
        let collector: String
        /// The value.
        let value: Double
    }

    /// Paths whose numbers come from SwiftProjectLint rather than SwiftStats.
    private static let swiftProjectLintPaths: Set<String> = ["api.overExposed", "tests.swiftTestingWithoutAssertions"]
    /// Roll-up fields whose next key names the tool.
    private static let perToolFields: Set<String> = ["findings", "findingKinds"]
    /// The roll-up field whose numbers come from SwiftEffectInference.
    private static let effectsField = "effects"
    /// The roll-up field whose numbers come from SwiftInferProperties.
    private static let propertiesField = "properties"

    /// Every number in `rollup`, sorted by path. Nulls and booleans are left
    /// out: a null is a value not collected, and a flag isn't a metric.
    static func metrics(of rollup: Rollup) throws -> [Metric] {
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(rollup))
        var metrics: [Metric] = []
        flatten(value, path: [], into: &metrics)
        return metrics.sorted { $0.path < $1.path }
    }

    /// The collector a metric at `path` comes from.
    static func collector(of path: [String]) -> String {
        if let field = path.first, perToolFields.contains(field), path.count > 1 {
            return path[1]
        }
        if swiftProjectLintPaths.contains(path.joined(separator: ".")) {
            return SwiftProjectLintAdapter.name
        }
        if path.first == effectsField {
            return EffectCollector.name
        }
        if path.first == propertiesField {
            return SwiftInferPropertiesAdapter.name
        }
        return SwiftStatsCollector.name
    }

    /// Appends each number under `value` to `metrics`.
    private static func flatten(_ value: JSONValue, path: [String], into metrics: inout [Metric]) {
        switch value {
        case .object(let members):
            for (key, child) in members {
                flatten(child, path: path + [key], into: &metrics)
            }

        case .number(let number):
            metrics.append(Metric(path: path.joined(separator: "."), collector: collector(of: path), value: number))

        case .array, .bool, .string, .null:
            break
        }
    }
}
