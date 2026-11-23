//
//  MutationVerdict.swift
//  SwiftStatsCore
//
//  A mutant's verdict (M6, design "Verdicts"), from a results line's raw
//  `outcome`, `activated`, `endedBy` and `leftOutWithOthers`, or, for an
//  entry of the last header's `mutantsNotCovered` with no line of its own,
//  `notCovered`: code no test ran, of which SwiftMutator made no mutant.
//  The scan JSON and the store write it by name.
//

/// What became of a mutant.
public enum MutationVerdict: String, CaseIterable, Sendable {
    /// Not built: it didn't compile, or was taken out of the build.
    case buildError
    /// A test failed, or a test process crashed.
    case killed
    /// Made and tested, but its block never ran.
    case noCoverage
    /// In code no test ran; listed by key, never made.
    case notCovered
    /// Ran, and every test passed.
    case survived
    /// Stopped at its time limit.
    case timedOut

    /// The raw outcomes a results line may record.
    static let outcomes: Set<String> = ["buildError", "failed", "noCoverage", "passed", "runtimeError", "timeout"]

    /// The verdict of a line recording `outcome`, `activated`, `endedBy`
    /// and `leftOutWithOthers`; nil for an outcome no SwiftMutator writes.
    /// A line that couldn't run, or was left out of the build with others,
    /// is a build error whatever its outcome; a pass whose block didn't run
    /// has no coverage.
    static func of(outcome: String, activated: MutantActivation, endedBy: String, leftOutWithOthers: Bool) -> Self? {
        guard outcomes.contains(outcome) else {
            return nil
        }
        if outcome == "buildError" || endedBy == "couldNotRun" || leftOutWithOthers {
            return .buildError
        }
        switch outcome {
        case "failed", "runtimeError":
            return .killed

        case "passed":
            return activated == .notRan ? .noCoverage : .survived

        case "noCoverage":
            return .noCoverage

        default:
            return .timedOut
        }
    }
}
