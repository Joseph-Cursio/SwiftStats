//
//  CoverageFileRuns.swift
//  SwiftStatsCore
//
//  A file's mapped lines as runs (M5): consecutive lines with one count
//  and the same partly-run flag share a run.
//

/// Mapped lines in runs.
enum CoverageFileRuns {
    /// `lines`, in order, as runs.
    static func runs(of lines: [CoverageLineIterator.Line]) -> [CoverageLineRun] {
        var runs: [CoverageLineRun] = []
        for line in lines {
            if let last = runs.last, last.end + 1 == line.line, last.count == line.executionCount,
               last.partlyRun == line.partlyRun {
                runs[runs.count - 1] = CoverageLineRun(
                    start: last.start,
                    end: line.line,
                    count: last.count,
                    partlyRun: last.partlyRun
                )
            } else {
                runs.append(CoverageLineRun(
                    start: line.line,
                    end: line.line,
                    count: line.executionCount,
                    partlyRun: line.partlyRun
                ))
            }
        }
        return runs
    }
}
