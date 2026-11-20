//
//  SwiftInferIndex.swift
//  SwiftStatsCore
//
//  `.swiftinfer/index.json` as `swift-infer index` writes it, schema 5
//  (PRD §7.11). Fields added after its first version are optional, as in
//  SwiftInferProperties' own decoder. Timestamps, `typeShapes` and
//  `sourceFileByTypeName` aren't read; locations are absolute paths in the
//  directory the tool ran in, made relative to it here.
//

import Foundation

/// One target's `index.json`.
struct SwiftInferIndex: Decodable {
    /// Just the schema version, read before anything else.
    struct Header: Decodable {
        /// The index's schema version.
        let schemaVersion: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case entries, interactionEntries
    }

    /// The schema version this decoder reads.
    static let schemaVersion = 5

    /// Template suggestions.
    let entries: [SwiftInferEntry]
    /// Reducer and view-model invariants; empty in an index older than them.
    let interactionEntries: [SwiftInferEntry]

    /// Decodes both lists.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([SwiftInferEntry].self, forKey: .entries) ?? []
        interactionEntries = try container.decodeIfPresent([SwiftInferEntry].self, forKey: .interactionEntries) ?? []
    }

    /// The index in `data`, or an error when its schema isn't the one read here.
    static func decode(_ data: Data) throws -> Self {
        let name = SwiftInferPropertiesAdapter.name
        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw AdapterError.unreadableOutput(name, String(describing: error))
        }
        guard header.schemaVersion == schemaVersion else {
            let found = header.schemaVersion.map(String.init) ?? "none"
            throw AdapterError.unknownSchema(name, found: found, expected: schemaVersion)
        }
        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            throw AdapterError.unreadableOutput(name, String(describing: error))
        }
    }

    /// `location` with its file relative to `root` when it is an absolute
    /// path inside it, however `root` is spelled; any other location as written.
    static func relative(_ location: String, under root: URL) -> String {
        guard location.hasPrefix("/"), let colon = location.lastIndex(of: ":") else {
            return location
        }
        let file = String(location[..<colon])
        for base in PathSpellings.of(root) where file.hasPrefix(base + "/") {
            return String(file.dropFirst(base.count + 1)) + location[colon...]
        }
        return RelativePath.of(file, under: root) + location[colon...]
    }

    /// Every row, written by `target` in `root`: template suggestions,
    /// then interaction invariants.
    func rows(target: String, root: URL) -> [SwiftInferRow] {
        entries.map { $0.row(.algebraic, target: target, root: root) }
            + interactionEntries.map { $0.row(.interaction, target: target, root: root) }
    }
}
