//
//  LoggedRun.swift
//  SwiftStatsCore
//
//  What a logged run of `ProcessRunner` needs besides its command: the log
//  its output streams are appended to, and how an interruption stops it
//  (`StopPolicy`), so SwiftMutator gets its own policy (M6, design §1.6).
//

import Foundation

/// The log a logged run appends to and how an interruption stops it.
struct LoggedRun {
    /// The file both output streams are appended to; it must exist.
    let log: URL
    /// How an interruption stops the run.
    let stop: StopPolicy
}
