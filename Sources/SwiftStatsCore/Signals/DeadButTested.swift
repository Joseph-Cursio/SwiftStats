//
//  DeadButTested.swift
//  SwiftStatsCore
//
//  Dead but tested (PRD §8, M7, design §8.2, D7): production functions no
//  production code uses, by outskirts, whose mutants the tests run. The
//  rule is stated here so a left-out signal says what it judges; the
//  functions are judged in plan step 9b, and until then the engine leaves
//  the signal out as not built yet once its requirements hold.
//

/// The dead but tested signal.
enum DeadButTested {
    /// The rule as reports state it, before the funnels.
    static let rule = "production functions no production code uses (outskirts with test targets not counted as "
        + "roots; public API of library-product modules, Codable and Equatable/Hashable/Comparable properties "
        + "retained) whose mutants the tests run (killed, survived or timed out; killed only, for files mutated "
        + "with coverage off); delete the code and its tests, which frees test and mutation time; a function "
        + "called only from an inactive #if branch reads as unused (outskirts' limit); types and properties "
        + "aren't judged"
}
