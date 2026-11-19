//
//  FindingCounts.swift
//  SwiftStatsCore
//
//  Findings per function, tool and rule on each side of a diff (PRD §6.6),
//  for tools whose results compare.
//

/// Counts of function-attached findings by owner key.
struct FindingCounts {
    /// Counts in the older snapshot: owner key → `findings.<tool>.<rule>` → count.
    let old: [String: [String: Int]]
    /// Counts in the newer snapshot.
    let new: [String: [String: Int]]

    /// The counts of `old` and `new` findings from `tools`.
    init(old: [FindingRow], new: [FindingRow], tools: Set<String>) {
        self.old = Self.count(old, tools: tools)
        self.new = Self.count(new, tools: tools)
    }

    /// Function-attached `rows` from `tools`, counted by owner and metric name.
    private static func count(_ rows: [FindingRow], tools: Set<String>) -> [String: [String: Int]] {
        var counts: [String: [String: Int]] = [:]
        for row in rows where row.attachedTo == .function && tools.contains(row.tool) {
            guard let owner = row.owner else {
                continue
            }
            counts[owner, default: [:]]["findings.\(row.tool).\(row.rule)", default: 0] += 1
        }
        return counts
    }
}
