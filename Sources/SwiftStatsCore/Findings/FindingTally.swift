//
//  FindingTally.swift
//  SwiftStatsCore
//
//  Counts findings for roll-ups (PRD §7.16): by tool and rule, and by tool
//  and kind. A tool that didn't run has no entry, rather than zeros (§6.5).
//

/// Findings to count, and the tools that ran.
struct FindingTally {
    /// Every finding.
    let findings: [Finding]
    /// The tools whose results are in `findings`, including ones that found nothing.
    let tools: Set<String>

    /// Counts by tool, then rule, of the findings whose first location is in `files`.
    func byRule(in files: Set<String>) -> [String: [String: Int]] {
        counts(in: files, by: \.rule)
    }

    /// Counts by tool, then kind, of the findings whose first location is in `files`.
    func byKind(in files: Set<String>) -> [String: [String: Int]] {
        counts(in: files) { $0.kind.rawValue }
    }

    /// Counts by tool, then `group`, every tool that ran having an entry.
    private func counts(in files: Set<String>, by group: (Finding) -> String) -> [String: [String: Int]] {
        var result = Dictionary(uniqueKeysWithValues: tools.map { ($0, [String: Int]()) })
        for finding in findings {
            guard let file = finding.locations.first?.file, files.contains(file) else {
                continue
            }
            result[finding.tool, default: [:]][group(finding), default: 0] += 1
        }
        return result
    }
}
