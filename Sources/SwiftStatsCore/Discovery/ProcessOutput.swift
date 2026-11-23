//
//  ProcessOutput.swift
//  SwiftStatsCore
//
//  What a finished command left behind, and how it ended.
//

import Foundation

/// A finished command's exit status and output.
struct ProcessOutput {
    /// The exit status, or the number of the signal that ended it.
    let status: Int32
    /// Whether it exited or a signal ended it.
    let termination: ProcessTermination
    /// Standard output.
    let output: Data
    /// Standard error, decoded as UTF-8 (empty when it isn't).
    let errorText: String

    /// What `process`, which has exited, left: `output` and `errorText`.
    init(process: Process, output: Data, errorText: String) {
        status = process.terminationStatus
        termination = ProcessTermination(process)
        self.output = output
        self.errorText = errorText
    }
}
