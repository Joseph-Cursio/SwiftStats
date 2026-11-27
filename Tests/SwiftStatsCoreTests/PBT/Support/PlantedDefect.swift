//
//  PlantedDefect.swift
//  SwiftStatsCoreTests
//
//  The mutant meta-test of design D15: a property's shared check, fed the
//  output of a planted defect, must catch it. The check records an issue
//  for each law that fails, so those issues are expected and run inside
//  `withKnownIssue`; the expectation that the check returned `false` runs
//  outside it. Inside, a failed expectation would be one more known issue,
//  and a check that let the defect through would pass the meta-test. Here
//  a missed defect fails twice: `withKnownIssue` reports that no known
//  issue was recorded, and the outer expectation fails.
//

import Testing

/// Meta-tests that a property's check catches a planted defect's output.
enum PlantedDefect {
    /// Expects `check`, fed the output of the planted defect `defect`
    /// names, to catch it: to record at least one issue, each known, and
    /// to return `false`. Records an issue at `sourceLocation` (the caller
    /// passes `#_sourceLocation`) when the check records none, and another
    /// when it returns `true`.
    static func expectCaught(
        _ defect: String,
        sourceLocation: SourceLocation,
        by check: () -> Bool
    ) {
        var passed = true
        withKnownIssue(Comment(rawValue: defect), sourceLocation: sourceLocation) {
            passed = check()
        }
        #expect(passed == false, "the check let a planted defect through: \(defect)", sourceLocation: sourceLocation)
    }
}
