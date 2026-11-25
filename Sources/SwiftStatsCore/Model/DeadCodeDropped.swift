//
//  DeadCodeDropped.swift
//  SwiftStatsCore
//
//  The entries of one outskirts run that aren't production code, by class
//  (M7, design §5.3): counted, never mapped to records or counted in a
//  metric.
//

/// One run's entries left out of the mapping, by class.
public struct DeadCodeDropped: Codable, Hashable, Sendable {
    /// Under the build directory.
    public let build: Int
    /// In a file that changed during the scan.
    public let fileChanged: Int
    /// Local variables.
    public let local: Int
    /// Outside the package root.
    public let outsideRoot: Int
    /// In a test target.
    public let test: Int
    /// In the root, in a file the scan didn't parse.
    public let unscanned: Int

    /// Creates the counts. Fields are documented on their properties.
    public init(build: Int, fileChanged: Int, local: Int, outsideRoot: Int, test: Int, unscanned: Int) {
        self.build = build
        self.fileChanged = fileChanged
        self.local = local
        self.outsideRoot = outsideRoot
        self.test = test
        self.unscanned = unscanned
    }

    /// The counts of `classes`, one per entry.
    init(_ classes: [PeripheryEntryClass]) {
        self.init(
            build: classes.count { $0 == .build },
            fileChanged: classes.count { $0 == .fileChanged },
            local: classes.count { $0 == .local },
            outsideRoot: classes.count { $0 == .outsideRoot },
            test: classes.count { $0 == .test },
            unscanned: classes.count { $0 == .unscanned }
        )
    }
}
