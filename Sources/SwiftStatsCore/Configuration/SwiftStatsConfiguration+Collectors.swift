//
//  SwiftStatsConfiguration+Collectors.swift
//  SwiftStatsCore
//
//  The `collectors` key (PRD §10.1, §7.16): per collector, `enabled` and
//  `path`, though a collector SwiftStats runs in process takes no `path`;
//  the coverage and swiftmutator collectors also take `arguments` (M5, M6),
//  and swiftmutator reads `options` (`workers`, `timeout`; M6). The T1
//  group's `build` takes no `path` either, since it uses the coverage
//  collector's `swift` (M7). `options` under any other collector, and
//  collectors no milestone has built yet, are accepted with a warning; any
//  other key is an error.
//

import Yams

extension SwiftStatsConfiguration {
    /// Collectors SwiftStats runs.
    static let builtCollectors: Set<String> = [
        "build", "coverage", "dependencies", "index", "periphery", "swiftclonedetector", "swifteffectinference",
        "swiftinferproperties", "swiftlint", "swiftmutator", "swiftprojectlint"
    ]
    /// Keys a collector's entry may hold.
    private static let collectorKeys: Set<String> = ["arguments", "enabled", "options", "path"]
    /// Collectors whose entry may hold `arguments`.
    private static let argumentCollectors: Set<String> = [CoverageAdapter.name, MutationAdapter.name]
    /// Collectors that read their entry's `options`.
    private static let optionCollectors: Set<String> = [MutationAdapter.name]
    /// Collectors SwiftStats runs in process, which take no `path`.
    private static let inProcessCollectors: Set<String> = ["index", "swifteffectinference"]

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
            if entryMapping["options"] != nil, optionCollectors.contains(name) == false {
                unused.insert("collectors.\(name).options")
            }
            guard builtCollectors.contains(name) else {
                unused.insert("collectors.\(name)")
                continue
            }
            let options = optionCollectors.contains(name)
                ? try MutationOptions.parse(entryMapping["options"], path: path)
                : (workers: nil, timeout: nil)
            settings[name] = CollectorSettings(
                enabled: try flag(entryMapping["enabled"], key: "collectors.\(name).enabled", path: path),
                path: try text(entryMapping["path"], key: "collectors.\(name).path", path: path),
                arguments: try CoverageArguments.parse(entryMapping["arguments"], name: name, path: path),
                workers: options.workers,
                timeout: options.timeout
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
        if argumentCollectors.contains(name) == false, mapping["arguments"] != nil {
            throw ScanError.configurationInvalid(
                path,
                "`collectors.\(name).arguments`: only the coverage and swiftmutator collectors take arguments"
            )
        }
        if inProcessCollectors.contains(name), mapping["path"] != nil {
            throw ScanError.configurationInvalid(
                path,
                "`collectors.\(name).path`: a collector SwiftStats runs itself has no path"
            )
        }
        if name == BuildAdapter.name, mapping["path"] != nil {
            throw ScanError.configurationInvalid(path, "`collectors.\(name).path`: \(BuildAdapter.pathError)")
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
