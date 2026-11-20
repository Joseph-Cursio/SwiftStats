//
//  SwiftStatsConfiguration+Collectors.swift
//  SwiftStatsCore
//
//  The `collectors` key (PRD §10.1, §7.16): per collector, `enabled` and
//  `path`, though a collector SwiftStats runs in process takes no `path`.
//  `options`, and collectors no milestone has built yet, are accepted with
//  a warning; any other key is an error.
//

import Yams

extension SwiftStatsConfiguration {
    /// Collectors SwiftStats runs.
    static let builtCollectors: Set<String> = ["dependencies", "swifteffectinference", "swiftlint", "swiftprojectlint"]
    /// Keys a collector's entry may hold.
    private static let collectorKeys: Set<String> = ["enabled", "options", "path"]
    /// Collectors SwiftStats runs in process, which take no `path`.
    private static let inProcessCollectors: Set<String> = ["swifteffectinference"]

    /// The settings `value` gives each collector, and the keys it holds that
    /// nothing reads yet, as `collectors.<name>[.options]`.
    static func collectorSettings(
        _ value: Node?,
        path: String
    ) throws -> (settings: [String: CollectorSettings], unused: Set<String>) {
        guard let value, value.null == nil else {
            return ([:], [])
        }
        guard let mapping = value.mapping else {
            throw ScanError.configurationInvalid(path, "`collectors` must be a mapping of collector names")
        }
        var settings: [String: CollectorSettings] = [:]
        var unused = Set<String>()
        for (key, entry) in mapping {
            guard let name = key.string else {
                throw ScanError.configurationInvalid(path, "`collectors` must be a mapping of collector names")
            }
            let entryMapping = try collectorMapping(entry, name: name, path: path)
            if entryMapping["options"] != nil {
                unused.insert("collectors.\(name).options")
            }
            guard builtCollectors.contains(name) else {
                unused.insert("collectors.\(name)")
                continue
            }
            settings[name] = CollectorSettings(
                enabled: try flag(entryMapping["enabled"], key: "collectors.\(name).enabled", path: path),
                path: try text(entryMapping["path"], key: "collectors.\(name).path", path: path)
            )
        }
        return (settings, unused)
    }

    /// The entry for collector `name` as a mapping holding only known keys.
    private static func collectorMapping(_ entry: Node, name: String, path: String) throws -> Node.Mapping {
        if entry.null != nil {
            return Node.Mapping([])
        }
        guard let mapping = entry.mapping else {
            throw ScanError.configurationInvalid(path, "`collectors.\(name)` must be a mapping")
        }
        let unknown = Set(mapping.keys.compactMap(\.string)).subtracting(collectorKeys).sorted()
        guard unknown.isEmpty else {
            let names = unknown.map { "collectors.\(name).\($0)" }.joined(separator: ", ")
            throw ScanError.configurationInvalid(path, "unknown key(s): \(names)")
        }
        if inProcessCollectors.contains(name), mapping["path"] != nil {
            throw ScanError.configurationInvalid(
                path,
                "`collectors.\(name).path`: a collector SwiftStats runs itself has no path"
            )
        }
        return mapping
    }

    /// A boolean, true when absent, or an error naming `key`.
    private static func flag(_ value: Node?, key: String, path: String) throws -> Bool {
        guard let value, value.null == nil else {
            return true
        }
        guard let flag = value.bool else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be true or false")
        }
        return flag
    }

    /// A string, nil when absent, or an error naming `key`.
    private static func text(_ value: Node?, key: String, path: String) throws -> String? {
        guard let value, value.null == nil else {
            return nil
        }
        guard let string = value.scalar?.string else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a path")
        }
        return string
    }
}
