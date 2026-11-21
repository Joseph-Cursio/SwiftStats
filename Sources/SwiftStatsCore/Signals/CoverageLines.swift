//
//  CoverageLines.swift
//  SwiftStatsCore
//
//  A snapshot's per-file line coverage (M5), looked up by file and line
//  for the coverage signals: a marker's line, a clone copy's range and the
//  lines in it no test ran, and whether a line lies in a skipped `#if`
//  range.
//

/// Each kept file's line data, by file.
struct CoverageLines {
    /// Each file's runs, by first line.
    private let runs: [String: [CoverageLineRun]]
    /// Each file's skipped ranges.
    private let skipped: [String: [CoverageLineRange]]

    /// The line data of `report`.
    init(_ report: CoverageReport) {
        var runsByFile: [String: [CoverageLineRun]] = [:]
        var skippedByFile: [String: [CoverageLineRange]] = [:]
        for file in report.files {
            runsByFile[file.file] = file.lines.sorted { $0.start < $1.start }
            skippedByFile[file.file] = file.skipped
        }
        runs = runsByFile
        skipped = skippedByFile
    }

    /// Whether the export holds line data for `file`.
    func holds(_ file: String) -> Bool {
        runs[file] != nil
    }

    /// The run holding `line` of `file`; nil when the line isn't mapped.
    func run(_ file: String, line: Int) -> CoverageLineRun? {
        // The last run starting at or before `line`, if it reaches it.
        guard let run = runs[file]?.last(where: { $0.start <= line }), run.end >= line else {
            return nil
        }
        return run
    }

    /// Whether `line` of `file` lies in a range an inactive `#if` skips.
    func isSkipped(_ file: String, line: Int) -> Bool {
        (skipped[file] ?? []).contains { $0.start <= line && line <= $0.end }
    }

    /// The mapped lines of `file` within `lines` that didn't run, in order.
    func uncovered(_ file: String, lines: ClosedRange<Int>) -> [Int] {
        (runs[file] ?? [])
            .filter { $0.ran == false && $0.end >= lines.lowerBound && $0.start <= lines.upperBound }
            .flatMap { max($0.start, lines.lowerBound)...min($0.end, lines.upperBound) }
    }

    /// The mapped lines of `file` within `lines`, and how many of them ran.
    func tally(_ file: String, lines: ClosedRange<Int>) -> CoverageTally {
        var covered = 0
        var mapped = 0
        for run in runs[file] ?? [] where run.end >= lines.lowerBound && run.start <= lines.upperBound {
            let overlap = min(run.end, lines.upperBound) - max(run.start, lines.lowerBound) + 1
            mapped += overlap
            if run.ran {
                covered += overlap
            }
        }
        return CoverageTally(covered: covered, total: mapped)
    }
}
