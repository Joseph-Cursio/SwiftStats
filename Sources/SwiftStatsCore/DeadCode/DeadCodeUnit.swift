//
//  DeadCodeUnit.swift
//  SwiftStatsCore
//
//  A covered unit of an outskirts run (M7, design §5.4): what an unused
//  production entry makes dead and whose lines count once. A type entry's
//  unit is the type (its type record and its extension records), an
//  extension entry's is its extension record, and every record an entry
//  covers is a unit of its own. Each unit has the regions it spans (its
//  main region first), a type's extension records apart, and the stripped
//  lines it adds per module.
//

/// A covered unit.
struct DeadCodeUnit: Hashable, Sendable {
    /// What the unit is.
    enum Kind: Hashable, Sendable {
        /// An extension record.
        case extensionRecord
        /// A function record, by key.
        case record(String)
        /// A type, by identity.
        case type(TypeIdentity)
    }

    /// A span of a file.
    struct Region: Hashable, Sendable {
        /// The file, in the package.
        let file: String
        /// The span.
        let span: SourceSpan
    }

    /// Lines a unit adds to a module.
    struct Part: Hashable, Sendable {
        /// The module, a target name.
        let module: String
        /// The stripped lines.
        let lines: Int
    }

    /// What separates the parts of an identifier.
    private static let separator = "\u{1F}"

    /// What the unit is.
    let kind: Kind
    /// Its identifier, unique among a run's units and ordering them.
    let identifier: String
    /// The regions it spans, its main region first.
    let regions: [Region]
    /// A type's extension records' regions; empty for other units.
    let extensions: Set<Region>
    /// The lines it adds, per module.
    let parts: [Part]

    /// The unit of `type`, named `identity`, with its extension records
    /// `extensions`.
    static func type(_ type: TypeRecord, identity: TypeIdentity, extensions: [TypeRecord]) -> Self {
        let spans = ([type] + extensions).map { Region(file: $0.file, span: $0.range) }
        return Self(
            kind: .type(identity),
            identifier: (["type"] + identity.parts).joined(separator: separator),
            regions: spans,
            extensions: Set(spans.dropFirst()),
            parts: ([type] + extensions).map { Part(module: $0.module, lines: $0.strippedLines) }
        )
    }

    /// The unit of the extension record `type`.
    static func extensionRecord(_ type: TypeRecord) -> Self {
        let start = type.range.start
        let end = type.range.end
        return Self(
            kind: .extensionRecord,
            identifier: ["extension", type.file, "\(start.line):\(start.column)-\(end.line):\(end.column)"]
                .joined(separator: separator),
            regions: [Region(file: type.file, span: type.range)],
            extensions: [],
            parts: [Part(module: type.module, lines: type.strippedLines)]
        )
    }

    /// The unit of the function record `record`.
    static func record(_ record: FunctionRecord) -> Self {
        Self(
            kind: .record(record.key),
            identifier: ["record", record.key].joined(separator: separator),
            regions: [Region(file: record.file, span: record.range)],
            extensions: [],
            parts: [Part(module: record.module, lines: record.strippedLines)]
        )
    }
}
