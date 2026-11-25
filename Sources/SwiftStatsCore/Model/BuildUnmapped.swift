//
//  BuildUnmapped.swift
//  SwiftStatsCore
//
//  The type-check timing entries no source position holds (M7, design
//  §6.2): synthesized members at `<invalid loc>`, and entries in macro
//  expansion buffers (results in macro expansions are unmapped, PRD §6.1a).
//

/// The timing entries that name no place in the package's files.
public struct BuildUnmapped: Codable, Hashable, Sendable {
    /// Synthesized members (`hash(into:)`), printed at `<invalid loc>`.
    public let synthesized: BuildEntryCount
    /// Entries in a `@__swiftmacro_…` buffer: Swift Testing's peers and
    /// expansions, among others.
    public let macro: BuildEntryCount

    /// Creates the counts. Fields are documented on their properties.
    public init(synthesized: BuildEntryCount, macro: BuildEntryCount) {
        self.synthesized = synthesized
        self.macro = macro
    }
}
