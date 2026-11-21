//
//  CoverageDropped.swift
//  SwiftStatsCore
//
//  The export's files the coverage mapping leaves out by design (M5),
//  counted and never listed.
//

/// How many of the export's files were dropped, by why.
public struct CoverageDropped: Codable, Hashable, Sendable {
    /// Under the coverage build directory or a `.build` directory:
    /// dependency checkouts, test runners, resource accessors.
    public let build: Int
    /// Outside the package root.
    public let outsideRoot: Int
    /// In a test target's directory.
    public let testFiles: Int
    /// Under the root but in no target's directory: a nested package or a
    /// path dependency.
    public let otherPackage: Int

    /// Creates the counts. Fields are documented on their properties.
    public init(build: Int, outsideRoot: Int, testFiles: Int, otherPackage: Int) {
        self.build = build
        self.outsideRoot = outsideRoot
        self.testFiles = testFiles
        self.otherPackage = otherPackage
    }
}
