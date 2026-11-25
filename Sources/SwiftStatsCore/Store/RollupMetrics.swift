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
    /// The roll-up field whose numbers come from SwiftCloneDetector.
    private static let clonesField = "clones"
    /// The roll-up field whose numbers come from the coverage collector.
    private static let coverageField = "coverage"
    /// The roll-up field whose numbers come from the SwiftMutator collector.
    private static let mutationField = "mutation"
    /// The roll-up field whose numbers come from the `index` collector.
    private static let indexField = "index"
    /// The roll-up field whose numbers come from the `periphery` collector.
    private static let deadCodeField = "deadCode"
    /// The line ratio's dead lines, which come from the `periphery`
    /// collector, though the rest of the ratio is SwiftStats' own (M7,
    /// design §7).
    private static let deadLinesPath = "tests.lineRatio.deadLines"
    /// The collector of each finding tool that isn't named after its
    /// collector: the compiler's warnings come from the T1 build (M7,
    /// design §6.4).
    private static let toolCollectors = [WarningReader.tool: BuildAdapter.name]

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
            return collector(ofTool: path[1])
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
        if path.first == clonesField {
            return SwiftCloneDetectorAdapter.name
        }
        if path.first == coverageField {
            return CoverageAdapter.name
        }
        if path.first == mutationField {
            return MutationAdapter.name
        }
        if path.first == indexField {
            return IndexAdapter.name
        }
        if path.first == deadCodeField || path.joined(separator: ".") == deadLinesPath {
            return PeripheryAdapter.name
        }
        return SwiftStatsCollector.name
    }

    /// The collector whose run gives the findings of `tool`: the tool's
    /// own name, but `build` for `swiftc`.
    static func collector(ofTool tool: String) -> String {
        toolCollectors[tool] ?? tool
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
