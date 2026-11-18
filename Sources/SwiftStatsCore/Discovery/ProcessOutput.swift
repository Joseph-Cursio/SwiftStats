//
//  ProcessOutput.swift
//  SwiftStatsCore
//
//  What a finished command left behind.
//

import Foundation

/// A finished command's exit status and output.
struct ProcessOutput {
    /// The exit status.
    let status: Int32
    /// Standard output.
    let output: Data
    /// Standard error, decoded as UTF-8 (empty when it isn't).
    let errorText: String
}
