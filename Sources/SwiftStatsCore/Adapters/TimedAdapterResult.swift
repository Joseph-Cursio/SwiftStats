//
//  TimedAdapterResult.swift
//  SwiftStatsCore
//
//  An external tool's run with what the snapshot records about it beyond
//  the scan JSON: the binary that ran and how long it took (PRD §6.2).
//

import Foundation

/// One adapter's result, the executable it ran and its run time.
struct TimedAdapterResult {
    /// What the run gave the scan.
    let result: AdapterResult
    /// The tool that ran; nil when it was skipped.
    let executable: URL?
    /// Wall-clock milliseconds.
    let milliseconds: Int
}
