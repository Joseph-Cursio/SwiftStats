//
//  CoverageFailure.swift
//  SwiftStatsCore
//
//  Why a coverage run failed (M5). Its text is the collector's reason, with
//  the package, its build directory and the toolchain already redacted.
//

/// A coverage run that failed, and why.
struct CoverageFailure: Error, Equatable, CustomStringConvertible {
    /// The reason, redacted.
    let description: String
}
