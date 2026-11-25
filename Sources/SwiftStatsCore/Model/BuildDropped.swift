//
//  BuildDropped.swift
//  SwiftStatsCore
//
//  The type-check timing entries the mapping leaves out (M7, design §6.2):
//  those under the build directory (dependencies, Swift Build's generated
//  `test_entry_point.swift`), outside the package root (a path
//  dependency), in a file that changed during the scan, and in a file of
//  the root the scan didn't parse.
//

/// The timing entries left out of the mapping, by why.
public struct BuildDropped: Codable, Hashable, Sendable {
    /// Under the build directory.
    public let build: BuildEntryCount
    /// Outside the package root.
    public let outsideRoot: BuildEntryCount
    /// In a scanned file whose bytes changed after the scan read them.
    public let fileChanged: BuildEntryCount
    /// In the root, in a file the scan didn't parse.
    public let unscanned: BuildEntryCount

    /// Creates the counts. Fields are documented on their properties.
    public init(
        build: BuildEntryCount,
        outsideRoot: BuildEntryCount,
        fileChanged: BuildEntryCount,
        unscanned: BuildEntryCount
    ) {
        self.build = build
        self.outsideRoot = outsideRoot
        self.fileChanged = fileChanged
        self.unscanned = unscanned
    }
}
