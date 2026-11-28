//
//  ExpandRuns.swift
//  SwiftStatsCoreTests
//
//  The inverse P2.4 checks `CoverageFileRuns.runs(of:)` against, written
//  from `CoverageLineRun`'s doc comments, not from the code that builds
//  runs: a run holds every line from its first to its last, inclusive,
//  each with the run's count and partly-run flag. So expanding runs, in
//  order, lists their lines one by one; a run whose last line comes before
//  its first holds none.
//

@testable import SwiftStatsCore

/// Runs expanded back into lines.
enum ExpandRuns {
    /// Every line `runs` hold, in order, each with its run's count and
    /// partly-run flag.
    static func lines(of runs: [CoverageLineRun]) -> [CoverageLineIterator.Line] {
        runs.flatMap { run -> [CoverageLineIterator.Line] in
            guard run.start <= run.end else {
                return []
            }
            return (run.start...run.end).map { line in
                CoverageLineIterator.Line(line: line, executionCount: run.count, partlyRun: run.partlyRun)
            }
        }
    }

    /// Whether `earlier` and `later`, adjacent runs, could be one run:
    /// `later` starts on the line after `earlier` ends, with the same count
    /// and partly-run flag.
    static func couldMerge(_ earlier: CoverageLineRun, _ later: CoverageLineRun) -> Bool {
        earlier.end < Int.max && earlier.end + 1 == later.start && earlier.count == later.count
            && earlier.partlyRun == later.partlyRun
    }
}
