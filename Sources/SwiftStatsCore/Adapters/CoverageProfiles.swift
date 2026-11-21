//
//  CoverageProfiles.swift
//  SwiftStatsCore
//
//  What a coverage run that ran leaves for the mapping (M5): the export of
//  every test bundle over all the run's profiles, the bundles, how the
//  tests went, and which functions each test target's own processes ran.
//

import Foundation

/// A finished coverage run's data, before it is mapped to records.
struct CoverageProfiles: Sendable {
    /// `llvm-cov export` of every bundle over the merged profiles, as JSON:
    /// `<build>/swiftstats-export.json`.
    let export: URL
    /// The test bundles, each a test target, sorted.
    let bundles: [String]
    /// `swift test`'s exit status: 0 when the tests passed.
    let testStatus: Int32
    /// Whether some bundle's framework wrote more than one profile (an exit
    /// test's child), so a crash after it may have gone unseen.
    let hasExtraProfiles: Bool
    /// By test target, the entry count of each function its own processes
    /// ran, by normalised mangled name; a function missing ran 0 times.
    let counts: [String: [String: Int64]]
}
