//
//  TargetSummary.swift
//  SwiftStatsCore
//
//  The targets a scan covered, as `Package.swift` declares them, so a reader
//  can see which files were production code and which were tests.
//

/// One scanned target.
public struct TargetSummary: Codable, Hashable, Sendable {
    /// The target name, which is also its module name.
    public let name: String
    /// The target type as SwiftPM describes it (`library`, `executable`,
    /// `test`, `macro`, `plugin`).
    public let type: String
    /// Whether the target holds tests (`true` for `test` targets).
    public let isTest: Bool
    /// The target's source directory, relative to the package root.
    public let path: String
    /// The Swift files scanned in the target, relative to the package root.
    public let files: [String]
    /// The package's own targets this one depends on, sorted.
    public let dependencies: [String]

    /// Creates a summary. Fields are documented on their properties.
    public init(name: String, type: String, isTest: Bool, path: String, files: [String], dependencies: [String] = []) {
        self.name = name
        self.type = type
        self.isTest = isTest
        self.path = path
        self.files = files
        self.dependencies = dependencies
    }
}
