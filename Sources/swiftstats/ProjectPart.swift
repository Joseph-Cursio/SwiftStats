//
//  ProjectPart.swift
//  swiftstats
//
//  The project parts a trend can follow: production code or test code.
//

import ArgumentParser

/// The project parts a trend can follow.
enum ProjectPart: String, ExpressibleByArgument, CaseIterable {
    /// Production code.
    case production
    /// Test code.
    case tests
}
