//
//  MetricsInfo.swift
//  SwiftStatsCore
//
//  Which SwiftCodeMetrics release and definitions scored a scan (PRD §7.3),
//  so a change of definition is never trended as a change of code.
//

/// The SwiftCodeMetrics versions behind every complexity score in a report.
public struct MetricsInfo: Codable, Hashable, Sendable {
    /// The SwiftCodeMetrics release.
    public let library: String
    /// The complexity definition version, such as `complexity-1`.
    public let complexityDefinition: String
    /// The SwiftLint release the SwiftLint-compatible count was checked against.
    public let swiftLintReference: String
    /// Whether the package's `.swiftlint.yml` sets
    /// `cyclomatic_complexity.ignores_case_statements`, which the
    /// SwiftLint-compatible count honours.
    public let swiftLintIgnoresCaseStatements: Bool

    /// Creates the information. Fields are documented on their properties.
    public init(
        library: String,
        complexityDefinition: String,
        swiftLintReference: String,
        swiftLintIgnoresCaseStatements: Bool
    ) {
        self.library = library
        self.complexityDefinition = complexityDefinition
        self.swiftLintReference = swiftLintReference
        self.swiftLintIgnoresCaseStatements = swiftLintIgnoresCaseStatements
    }
}
