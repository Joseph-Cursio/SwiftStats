//
//  CoverageProfile.swift
//  SwiftStatsCore
//
//  One raw profile a coverage run's `swift test` wrote (M5). SwiftPM runs
//  each test bundle twice, once under XCTest and once under Swift Testing,
//  and each process writes `<XCTest|Swift Testing><signature>_<n>.<pid>.profraw`
//  into the bin path's `codecov`; a bundle's two processes share the
//  signature, and an exit test's child process adds another profile with it.
//

import Foundation

/// One `.profraw` file of a coverage run.
struct CoverageProfile: Hashable, Sendable {
    /// The XCTest framework's name in a profile's name.
    static let xcTest = "XCTest"
    /// The Swift Testing framework's name in a profile's name.
    static let swiftTesting = "Swift Testing"
    /// Every framework whose process each bundle runs, in the order
    /// SwiftPM runs them.
    static let frameworks = [xcTest, swiftTesting]
    /// The extension of a raw profile.
    static let fileExtension = "profraw"

    /// The file.
    let url: URL
    /// The framework whose process wrote it.
    let framework: String
    /// The signature it shares with the other profiles of its bundle.
    let signature: String
    /// Whether it holds no bytes: its process died before writing it.
    let isEmpty: Bool

    /// The profile at `url`, whose size is `size` bytes; nil when its name
    /// doesn't follow the grammar.
    init?(url: URL, size: Int) {
        let pattern = /(XCTest|Swift Testing)([0-9]+)_[0-9]+\.[0-9]+\.profraw/
        guard let match = url.lastPathComponent.wholeMatch(of: pattern) else {
            return nil
        }
        self.url = url
        framework = String(match.output.1)
        signature = String(match.output.2)
        isEmpty = size == 0
    }
}
