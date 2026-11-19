//
//  CommitFacts.swift
//  SwiftStatsCore
//
//  What history needs to know about each commit besides its events: when
//  it was made, whether it is in the window, whether it is a sweep, a fix
//  or a revert, and which tests it changed.
//

/// One commit's classification.
struct CommitFacts: Sendable {
    /// Committer time, in seconds since 1970.
    let time: Int
    /// Whether it falls in the window.
    let inWindow: Bool
    /// The package's Swift files it changed.
    let files: Int
    /// Why it is a sweep (`sweep` or `ignored`); nil when it isn't.
    let sweepReason: String?
    /// Whether its subject matches a fix pattern.
    let matchesFix: Bool
    /// Whether its subject matches a fix-exclusion pattern.
    let excludedSubject: Bool
    /// Whether it is a revert.
    let isRevertCommit: Bool
    /// The test names of the test files it changed.
    let testNames: Set<String>

    /// Whether it counts as a sweep.
    var isSweep: Bool {
        sweepReason != nil
    }

    /// Whether it counts as a fix: a matching subject that isn't excluded,
    /// and not a sweep.
    var isFix: Bool {
        matchesFix && excludedSubject == false && isSweep == false
    }

    /// Whether it counts as a revert.
    var isRevert: Bool {
        isRevertCommit && isSweep == false
    }

    /// Why a matching commit doesn't count, for the report.
    var exclusion: String? {
        sweepReason ?? (excludedSubject ? "excluded-subject" : nil)
    }
}
