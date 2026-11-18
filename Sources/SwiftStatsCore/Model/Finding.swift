//
//  Finding.swift
//  SwiftStatsCore
//
//  One result from SwiftProjectLint, SwiftLint or SwiftStats' own marker
//  pass, attached to the code it names (PRD §7.16).
//

/// A tool's result at one or more places.
public struct Finding: Codable, Hashable, Sendable {
    /// The tool: `swiftprojectlint`, `swiftlint` or `swiftstats`.
    public let tool: String
    /// The rule: SwiftProjectLint's case name, SwiftLint's rule identifier,
    /// or SwiftStats' marker name.
    public let rule: String
    /// The tool's category for the rule, when it has one.
    public let category: String?
    /// Census or defect.
    public let kind: FindingKind
    /// The tool's severity, lowercased.
    public let severity: String
    /// The tool's message.
    public let message: String
    /// The declaration the tool names, when it names one.
    public let symbol: String?
    /// Where it is; the first location decides its module in roll-ups.
    public let locations: [FindingLocation]

    /// Creates a finding. Fields are documented on their properties.
    public init(
        tool: String,
        rule: String,
        category: String?,
        kind: FindingKind,
        severity: String,
        message: String,
        symbol: String?,
        locations: [FindingLocation]
    ) {
        self.tool = tool
        self.rule = rule
        self.category = category
        self.kind = kind
        self.severity = severity
        self.message = message
        self.symbol = symbol
        self.locations = locations
    }
}
