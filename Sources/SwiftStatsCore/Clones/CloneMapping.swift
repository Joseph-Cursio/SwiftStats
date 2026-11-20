//
//  CloneMapping.swift
//  SwiftStatsCore
//
//  The clone report and, per file, the lines its copies cover, which the
//  roll-ups count as a union (PRD §7.12). The line sets stay out of the
//  scan JSON; each copy records only its own count.
//

/// SwiftCloneDetector's classes attached to records, and the lines they cover.
struct CloneMapping {
    /// The report.
    let report: CloneReport
    /// The stripped lines any copy covers, by file.
    let linesByFile: [String: Set<Int>]
}
