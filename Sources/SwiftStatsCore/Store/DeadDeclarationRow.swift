//
//  DeadDeclarationRow.swift
//  SwiftStatsCore
//
//  The `deadDeclaration` table (store v6, M7, design §5.3, §9.1): one row
//  per entry of either outskirts run of a snapshot holding dead-code
//  results, dropped classes included, so a carry keeps them and the
//  dropped counts follow from them. Lists are JSON arrays; modules are
//  target names; the class and place are held by name.
//

import GRDB

/// An outskirts entry, as one row.
struct DeadDeclarationRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table's columns.
    private enum CodingKeys: String, CodingKey {
        case snapshotId
        case run
        case ordinal
        case hint
        case hintText
        case kind
        case name
        case accessibility
        case attributes
        case modifiers
        case ids
        case modules
        case entryClass = "class"
        case file
        case line
        case column
        case place
        case owner
        case module
        case strippedLines
    }

    /// The table name.
    static let databaseTableName = "deadDeclaration"

    /// The snapshot.
    var snapshotId: Int64
    /// The run, by name.
    var run: String
    /// Its 1-based position in the run's output.
    var ordinal: Int
    /// outskirts' hint.
    var hint: String
    /// The hint's text, when it has one.
    var hintText: String?
    /// The declaration kind.
    var kind: String
    /// The declared name.
    var name: String
    /// Its accessibility.
    var accessibility: String
    /// Its attributes, as a JSON array.
    var attributes: String
    /// Its modifiers, as a JSON array.
    var modifiers: String
    /// Its USRs, as a JSON array.
    var ids: String
    /// Its modules as target names, as a JSON array.
    var modules: String
    /// Its class, by name.
    var entryClass: String
    /// The file, relative to the package root; null outside it.
    var file: String?
    /// The line.
    var line: Int
    /// The column.
    var column: Int
    /// Where it is listed, by name.
    var place: String
    /// What it is listed under.
    var owner: String?
    /// The module it is listed in.
    var module: String?
    /// The stripped lines of what it covers.
    var strippedLines: Int?

    /// The declaration this row holds; it throws when a name or JSON
    /// column doesn't read.
    var declaration: DeadCodeDeclaration {
        get throws {
            DeadCodeDeclaration(
                run: try RowJSON.named(DeadCodeRun.self, from: run),
                ordinal: ordinal,
                hint: hint,
                hintText: hintText,
                kind: kind,
                name: name,
                accessibility: accessibility,
                attributes: try RowJSON.decoded([String].self, from: attributes),
                modifiers: try RowJSON.decoded([String].self, from: modifiers),
                ids: try RowJSON.decoded([String].self, from: ids),
                modules: try RowJSON.decoded([String].self, from: modules),
                entryClass: try RowJSON.named(PeripheryEntryClass.self, from: entryClass),
                file: file,
                line: line,
                column: column,
                place: try RowJSON.named(FindingTarget.self, from: place),
                owner: owner,
                module: module,
                strippedLines: strippedLines
            )
        }
    }

    /// The row for `declaration` in snapshot `snapshotId`.
    init(_ declaration: DeadCodeDeclaration, snapshotId: Int64) {
        self.snapshotId = snapshotId
        run = declaration.run.rawValue
        ordinal = declaration.ordinal
        hint = declaration.hint
        hintText = declaration.hintText
        kind = declaration.kind
        name = declaration.name
        accessibility = declaration.accessibility
        attributes = RowJSON.text(declaration.attributes)
        modifiers = RowJSON.text(declaration.modifiers)
        ids = RowJSON.text(declaration.ids)
        modules = RowJSON.text(declaration.modules)
        entryClass = declaration.entryClass.rawValue
        file = declaration.file
        line = declaration.line
        column = declaration.column
        place = declaration.place.rawValue
        owner = declaration.owner
        module = declaration.module
        strippedLines = declaration.strippedLines
    }
}
