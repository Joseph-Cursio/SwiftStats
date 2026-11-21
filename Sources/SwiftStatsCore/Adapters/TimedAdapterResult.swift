//
//  TimedAdapterResult.swift
//  SwiftStatsCore
//
//  An external tool's run with what the snapshot records about it beyond
//  the scan JSON: the binary that ran, the build identity when the run
//  established one itself, and how long it took (PRD §6.2).
//

import Foundation

/// One adapter's result, the executable it ran and its run time.
struct TimedAdapterResult {
    /// What the run gave the scan.
    let result: AdapterResult
    /// The tool that ran; nil when it was skipped.
    let executable: URL?
    /// The build identity the run established itself (the coverage
    /// collector's `swift:<version line>`); nil to identify the run by
    /// its executable's hash.
    let identity: String?
    /// Wall-clock milliseconds.
    let milliseconds: Int
}
