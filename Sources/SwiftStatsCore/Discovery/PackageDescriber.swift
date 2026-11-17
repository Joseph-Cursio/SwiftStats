//
//  PackageDescriber.swift
//  SwiftStatsCore
//
//  Asks SwiftPM what a package contains. `Package.swift` is Swift code and
//  SwiftPM's source-selection rules are intricate, so SwiftStats takes the
//  answer from SwiftPM rather than reimplementing either.
//

import Foundation

/// Describes the package at a directory.
public protocol PackageDescriber: Sendable {
    /// Returns the description of the package rooted at `packageRoot`.
    func describePackage(at packageRoot: URL) throws -> DescribedPackage
}
