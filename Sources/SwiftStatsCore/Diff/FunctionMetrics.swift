//
//  FunctionMetrics.swift
//  SwiftStatsCore
//
//  The metrics `diff` compares for a matched function record (PRD §6.6).
//

/// Compares one matched pair of records.
enum FunctionMetrics {
    /// The changed metrics of `old` → `new`, or nil when none changed.
    static func delta(_ old: FunctionRow, _ new: FunctionRow, counts: FindingCounts) -> FunctionDelta? {
        let before = values(of: old, findings: counts.old[old.key] ?? [:])
        let after = values(of: new, findings: counts.new[new.key] ?? [:])
        let metrics = Set(before.keys).union(after.keys).sorted().compactMap { name -> MetricDelta? in
            let previous = CountedMetrics.value(before[name], metric: name)
            let next = CountedMetrics.value(after[name], metric: name)
            return previous == next ? nil : MetricDelta(metric: name, before: previous, after: next)
        }
        return metrics.isEmpty ? nil : FunctionDelta(key: new.key, metrics: metrics)
    }

    /// Each metric of `row` that has a value, with its finding counts.
    private static func values(of row: FunctionRow, findings: [String: Int]) -> [String: Double] {
        let optional: [String: Double?] = [
            "strippedLines": Double(row.strippedLines),
            "parameterCount": row.parameterCount.map(Double.init),
            "cognitive": row.cognitive.map(Double.init),
            "decisionCount": row.decisionCount.map(Double.init),
            "swiftLintCompatible": row.swiftLintCompatible.map(Double.init),
            "maxNesting": row.maxNesting.map(Double.init),
            "isAsync": row.isAsync ? 1 : 0
        ]
        var values = optional.compactMapValues(\.self)
        for (name, count) in findings {
            values[name] = Double(count)
        }
        return values
    }
}
