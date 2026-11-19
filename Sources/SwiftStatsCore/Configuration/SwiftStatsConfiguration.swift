//
//  SwiftStatsConfiguration.swift
//  SwiftStatsCore
//
//  `.swiftstats.yml` (PRD §10.1). `excluded`, `generated`, `collectors`,
//  `store`, `history` and `signals` are read; any other key is an error.
//

import Foundation
import Yams

/// The scan's configuration.
public struct SwiftStatsConfiguration: Hashable, Sendable {
    /// The file name looked for in the package root.
    public static let fileName = ".swiftstats.yml"
    /// Keys the PRD names but no collector reads yet.
    private static let laterKeys: Set<String> = []
    /// Every key the file may hold.
    private static let knownKeys = laterKeys.union(
        ["collectors", "excluded", "generated", "history", "signals", "store"]
    )

    /// Path globs, relative to the package root, of files not to scan.
    public let excluded: [String]
    /// Path globs of generated files (PRD D8): `generated`, or the
    /// defaults when the file doesn't give it.
    public let generated: [String]
    /// `collectors.<name>` entries, by collector name.
    public let collectors: [String: CollectorSettings]
    /// Where the snapshot store is (PRD D9), relative to the package root
    /// or absolute; nil for the default `.swiftstats/stats.sqlite`.
    public let store: String?
    /// How the history collector reads git history (PRD §7.13).
    public let history: HistoryOptions
    /// The ranked signals' membership thresholds (PRD §8).
    public let signals: SignalThresholds
    /// Keys present in the file that no collector reads yet, sorted.
    public let unusedKeys: [String]
    /// The file the configuration came from, as warnings name it; nil for the default.
    public let source: String?

    /// A configuration with nothing excluded and the default generated globs.
    public init() {
        self.init(
            excluded: [],
            generated: GeneratedCode.defaultGlobs,
            collectors: [:],
            store: nil,
            history: .standard,
            signals: SignalThresholds(),
            unusedKeys: [],
            source: nil
        )
    }

    /// A configuration. Fields are documented on their properties.
    public init(
        excluded: [String],
        generated: [String],
        collectors: [String: CollectorSettings],
        store: String?,
        history: HistoryOptions,
        signals: SignalThresholds,
        unusedKeys: [String],
        source: String?
    ) {
        self.excluded = excluded
        self.generated = generated
        self.collectors = collectors
        self.store = store
        self.history = history
        self.signals = signals
        self.unusedKeys = unusedKeys
        self.source = source
    }

    /// The configuration in `file`, or the default when `file` is nil.
    /// Warnings name the file relative to `root` when it is inside it.
    static func load(_ file: URL?, root: URL) throws -> Self {
        guard let file else {
            return Self()
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ScanError.configurationInvalid(file.path, "no such file")
        }
        let text: String
        do {
            text = try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw ScanError.configurationInvalid(file.path, "not readable as UTF-8")
        }
        let rootPath = root.standardizedFileURL.path + "/"
        let filePath = file.standardizedFileURL.path
        let shown = filePath.hasPrefix(rootPath) ? String(filePath.dropFirst(rootPath.count)) : file.path
        return try parse(text, path: file.path, source: shown)
    }

    /// The configuration `text` holds; `path` names it in errors.
    static func parse(_ text: String, path: String) throws -> Self {
        try parse(text, path: path, source: path)
    }

    /// The configuration `text` holds, from `source`.
    private static func parse(_ text: String, path: String, source: String) throws -> Self {
        let node: Node?
        do {
            node = try Yams.compose(yaml: text)
        } catch {
            throw ScanError.configurationInvalid(path, "not valid YAML: \(error)")
        }
        guard let node, node.null == nil else {
            return Self(
                excluded: [],
                generated: GeneratedCode.defaultGlobs,
                collectors: [:],
                store: nil,
                history: .standard,
                signals: SignalThresholds(),
                unusedKeys: [],
                source: source
            )
        }
        guard let mapping = node.mapping else {
            throw ScanError.configurationInvalid(path, "the top level must be a mapping")
        }
        let keys = mapping.keys.compactMap(\.string)
        let repeated = Set(keys.filter { key in keys.filter { $0 == key }.count > 1 }).sorted()
        guard repeated.isEmpty else {
            let names = repeated.joined(separator: ", ")
            throw ScanError.configurationInvalid(path, "key(s) given more than once: \(names)")
        }
        let unknown = Set(keys).subtracting(knownKeys).sorted()
        guard unknown.isEmpty else {
            throw ScanError.configurationInvalid(path, "unknown key(s): \(unknown.joined(separator: ", "))")
        }
        let (settings, unusedCollectorKeys) = try collectorSettings(mapping["collectors"], path: path)
        return Self(
            excluded: try globs(mapping["excluded"], key: "excluded", path: path),
            generated: try mapping["generated"].map { try globs($0, key: "generated", path: path) }
                ?? GeneratedCode.defaultGlobs,
            collectors: settings,
            store: try storePath(mapping["store"], path: path),
            history: try historyOptions(mapping["history"], path: path),
            signals: try signalThresholds(mapping["signals"], path: path),
            unusedKeys: (Set(keys).intersection(laterKeys).union(unusedCollectorKeys)).sorted(),
            source: source
        )
    }

    /// The `store` path, or nil when absent; an error unless it is a string.
    private static func storePath(_ value: Node?, path: String) throws -> String? {
        guard let value, value.null == nil else {
            return nil
        }
        guard let text = value.scalar?.string, text.isEmpty == false else {
            throw ScanError.configurationInvalid(path, "`store` must be a path")
        }
        return text
    }

    /// A list of glob strings, or an error naming `key`. An absent or empty
    /// value is an empty list.
    private static func globs(_ value: Node?, key: String, path: String) throws -> [String] {
        guard let value, value.null == nil else {
            return []
        }
        guard let sequence = value.sequence else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a list of path globs")
        }
        return try sequence.map { item in
            guard let glob = item.scalar?.string else {
                throw ScanError.configurationInvalid(path, "`\(key)` must be a list of path globs")
            }
            return glob
        }
    }
}
