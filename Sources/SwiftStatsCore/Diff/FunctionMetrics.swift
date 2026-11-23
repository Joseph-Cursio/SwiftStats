//
//  FunctionMetrics.swift
//  SwiftStatsCore
//
//  The metrics `diff` compares for a matched function record (PRD §6.6),
//  its coverage percentages among them when coverage compares (M5), and
//  its mutation figures when SwiftMutator's results compare (M6).
//

/// Compares one matched pair of records.
enum FunctionMetrics {
    /// The changed metrics of `old` → `new`, with their finding `counts`,
    /// `coverage` and `mutation` figures, or nil when none changed.
    static func delta(
        _ old: FunctionRow,
        _ new: FunctionRow,
        counts: FindingCounts,
        coverage: CoverageMetrics,
        mutation: MutationMetrics
    ) -> FunctionDelta? {
        let before = values(
            of: old,
            findings: counts.old[old.key] ?? [:],
            measured: (coverage.old[old.key] ?? [:]).merging(mutation.old[old.key] ?? [:]) { first, _ in first }
        )
        let after = values(
            of: new,
            findings: counts.new[new.key] ?? [:],
            measured: (coverage.new[new.key] ?? [:]).merging(mutation.new[new.key] ?? [:]) { first, _ in first }
        )
        let metrics = Set(before.keys).union(after.keys).sorted().compactMap { name -> MetricDelta? in
            let previous = CountedMetrics.value(before[name], metric: name)
            let next = CountedMetrics.value(after[name], metric: name)
            return previous == next ? nil : MetricDelta(metric: name, before: previous, after: next)
        }
        return metrics.isEmpty ? nil : FunctionDelta(key: new.key, metrics: metrics)
    }

    /// Each metric of `row` that has a value, with its finding counts and
    /// the coverage and mutation figures `measured` for it.
    private static func values(
        of row: FunctionRow,
        findings: [String: Int],
        measured: [String: Double]
    ) -> [String: Double] {
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
        values.merge(measured) { first, _ in first }
        return values
    }
}
