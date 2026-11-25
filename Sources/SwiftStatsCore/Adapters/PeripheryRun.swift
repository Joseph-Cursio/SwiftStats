//
//  PeripheryRun.swift
//  SwiftStatsCore
//
//  What a run of the `periphery` collector gave (M7, design §5): its
//  result and run time, with the executable that ran, and, when it ran,
//  both runs' entries read and classed, and mapped onto the scan.
//

/// The `periphery` collector's run.
struct PeripheryRun {
    /// Its result, executable and run time.
    let timed: TimedAdapterResult
    /// Both runs' entries; nil unless it ran.
    let output: PeripheryOutput?
    /// The entries mapped onto the scan; nil unless it ran.
    let report: DeadCodeReport?
}
