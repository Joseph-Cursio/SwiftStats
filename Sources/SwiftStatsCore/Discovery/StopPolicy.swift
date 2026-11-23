//
//  StopPolicy.swift
//  SwiftStatsCore
//
//  How an interrupted command stops a process it started
//  (`ScratchRegistry`): the signal it sends first, how long the process
//  gets to end by it, then SIGTERM and a shorter wait unless the first
//  signal was SIGTERM already, then SIGKILL. Most tools get M5's
//  SIGINT-first policy: SwiftPM's `swift test` forwards SIGINT to the test
//  processes it started in process groups of their own, which neither
//  SIGTERM nor SIGKILL of `swift` reaches. SwiftMutator (M6, design §1.6)
//  gets SIGTERM and 35 seconds: it stops cleanly on its first signal,
//  killing the test processes only it can reach and writing its results
//  file's end line, and stops at once on a second signal or after 30
//  seconds of its own, so SwiftStats waits out that bound plus a margin
//  and sends no second signal before SIGKILL.
//

import Foundation

/// The signals an interrupted command sends a process it started, and the
/// waits between them.
struct StopPolicy: Equatable, Sendable {
    /// How long the standard policy gives SIGINT, in seconds.
    private static let standardGrace: TimeInterval = 2
    /// How long it then gives SIGTERM.
    private static let standardKillGrace: TimeInterval = 0.5
    /// How long SwiftMutator's policy gives SIGTERM: SwiftMutator's own
    /// 30-second bound plus a margin.
    private static let swiftMutatorGrace: TimeInterval = 35

    /// M5's policy, for every tool but SwiftMutator: SIGINT, 2 seconds,
    /// SIGTERM, half a second, SIGKILL.
    static let standard = Self(firstSignal: SIGINT, grace: standardGrace, killGrace: standardKillGrace)
    /// SwiftMutator's: SIGTERM, 35 seconds, SIGKILL.
    static let swiftMutator = Self(firstSignal: SIGTERM, grace: swiftMutatorGrace, killGrace: 0)

    /// The signal sent first.
    let firstSignal: Int32
    /// How long the process gets to end by it.
    let grace: TimeInterval
    /// How long it then gets to end by SIGTERM before SIGKILL; not waited
    /// when the first signal was SIGTERM, which isn't sent twice.
    let killGrace: TimeInterval

    /// Whether a process still running after `grace` gets SIGTERM before
    /// SIGKILL.
    var terminates: Bool {
        firstSignal != SIGTERM
    }

    /// How long after the first signal a process still running gets
    /// SIGKILL.
    var killAfter: TimeInterval {
        grace + (terminates ? killGrace : 0)
    }
}
