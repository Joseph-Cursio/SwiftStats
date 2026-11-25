//
//  UnitFilter.swift
//  SwiftStatsCore
//
//  Which units of the T1 build's index store are the package's current
//  compiles (M7, design §2.3). The store is append-only: a rebuilt file's
//  unit is rewritten in place, but a deleted or renamed file's unit stays,
//  and so does a file's unit for a target it has left. Each unit gets the
//  first class that applies: `system` (an SDK interface), `otherPackage`
//  (no main file, or one outside the package root's real path, under the
//  scratch folder, `.swiftstats`, `.build` or a local path dependency's
//  folder: dependency checkouts, local packages nested in the root and
//  Swift Build's generated test entry points), `otherModule` (its module
//  is no target's C99 name in the T1 describe), `stale` (its main file is
//  gone, or isn't a source of the target its module maps to), `duplicate`
//  (another unit of the same module, main file and triple is newer: the
//  later modification date, then the larger unit name), `variant` (kept
//  and read, but another kept unit has the same module and main file with
//  another triple: every unit of such a group is a variant), and `kept`.
//  Paths are compared in NFC, as the reader gives them; the describe's
//  target paths and sources are joined as `TargetResolver` joins them, so
//  a target at `.` matches.
//
//  The quarantine then moves the `stale` and `otherModule` units under the
//  root out of `<scratch>/out/v5/units` into
//  `<scratch>/swiftstats-quarantined-units` (emptied first), since
//  outskirts reads the store itself and would keep a moved file's
//  old-module unit. The folder is SwiftStats' own and Swift Build never
//  reads unit files back; a later compile of the file writes a new unit.
//

import Foundation

/// Classes the units of the T1 build's index store.
struct UnitFilter: Sendable {
    /// A unit's class, the first that applies in the order of the cases'
    /// documentation in this file's header.
    typealias UnitClass = IndexUnitClass

    /// A unit and its class.
    struct ClassedUnit: Hashable, Sendable {
        /// The unit.
        let unit: IndexUnitFact
        /// Its class.
        let unitClass: UnitClass
    }

    /// Why moving units out of the store failed.
    struct QuarantineFailure: Error, CustomStringConvertible {
        /// The failure, for the `index` collector's reason.
        let description: String
    }

    /// The folder under the scratch folder that quarantined units are
    /// moved to.
    static let quarantineDirectory = "swiftstats-quarantined-units"
    /// The rule, as the `index` collector's `units:` option states it.
    static let rule = "kept: non-system units whose main file exists under the package root outside .swiftstats, "
        + ".build and local path dependencies' folders and is a source of the target whose C99 name is the unit's "
        + "module (T1 describe); newest per module, file and triple; other triples read as variants; stale and "
        + "other-module units moved out before outskirts runs"
    /// The first path components under the root whose files are never the
    /// package's sources.
    private static let buildFolders: Set<String> = [".build", ".swiftstats"]

    /// The package root's real path, in NFC.
    let root: String
    /// The scratch folder's real path, in NFC.
    let scratch: String
    /// Each target's C99 module name, to its target name.
    let modules: [String: String]
    /// Each target's sources, by target name, as paths in the package in
    /// NFC.
    private let sources: [String: Set<String>]
    /// The real paths of the describe's local path dependencies, in NFC:
    /// their files are another package's even when under the root.
    private let dependencyRoots: [String]

    /// A filter for the package at `root` (its real path), built into
    /// `scratch` (the scratch folder's real path), as the T1 describe
    /// `package` describes it; fails when two targets share a C99 name.
    init(root: String, scratch: String, package: DescribedPackage) throws {
        self.root = root.precomposedStringWithCanonicalMapping
        self.scratch = scratch.precomposedStringWithCanonicalMapping
        modules = try BuildSession.moduleMap(of: package)
        var paths: [String: Set<String>] = [:]
        for target in package.targets {
            let directory = TargetResolver.normalised(target.path)
            paths[target.name, default: []].formUnion(target.sources.map { source in
                TargetResolver.normalised(directory.isEmpty ? source : directory + "/" + source)
                    .precomposedStringWithCanonicalMapping
            })
        }
        sources = paths
        let base = self.root
        dependencyRoots = package.dependencies
            .filter { $0.type == "fileSystem" }
            .map { Self.realPath(of: $0.location, from: base).precomposedStringWithCanonicalMapping }
            .sorted()
    }

    /// `location` (absolute, or relative to `root`) as a real path
    /// (realpath(3)); its joined path when it can't be resolved.
    private static func realPath(of location: String, from root: String) -> String {
        let path = location.hasPrefix("/") ? location : root + "/" + location
        guard let resolved = realpath(path, nil) else {
            return path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Whether `path` (absolute, in NFC) is a local path dependency's root
    /// or under one.
    private func isInDependency(_ path: String) -> Bool {
        dependencyRoots.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// The target name of module `module` (a C99 name), or nil when it is
    /// no target's.
    func target(of module: String) -> String? {
        modules[module]
    }

    /// `path` (absolute) as a path in the package, or nil when it isn't
    /// under the root.
    func packagePath(of path: String) -> String? {
        let normalized = path.precomposedStringWithCanonicalMapping
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard normalized.hasPrefix(prefix), normalized.count > prefix.count else {
            return nil
        }
        return String(normalized.dropFirst(prefix.count))
    }

    /// Every unit of `units` with its class, sorted by unit name.
    func classify(_ units: [IndexUnitFact]) -> [ClassedUnit] {
        var classes: [String: UnitClass] = [:]
        var candidates: [IndexUnitFact] = []
        for unit in units {
            if let unitClass = headerClass(of: unit) {
                classes[unit.name] = unitClass
            } else {
                candidates.append(unit)
            }
        }
        let byTriple = Dictionary(grouping: candidates) { [$0.module, $0.mainFile, $0.target] }
        var newest: [IndexUnitFact] = []
        for group in byTriple.values {
            let sorted = group.sorted { ($0.modified, $0.name) > ($1.modified, $1.name) }
            newest.append(sorted[0])
            for older in sorted.dropFirst() {
                classes[older.name] = .duplicate
            }
        }
        for group in Dictionary(grouping: newest, by: { [$0.module, $0.mainFile] }).values {
            let triples = Set(group.map(\.target))
            for unit in group {
                classes[unit.name] = triples.count > 1 ? .variant : .kept
            }
        }
        return units
            .sorted { $0.name < $1.name }
            .compactMap { unit in classes[unit.name].map { ClassedUnit(unit: unit, unitClass: $0) } }
    }

    /// Moves the units of `classed` that the quarantine takes (`stale` and
    /// `otherModule` units whose main file is under the root) from the
    /// store's `v5/units` into the quarantine folder, emptied first, and
    /// returns their names, sorted.
    func quarantine(_ classed: [ClassedUnit]) throws -> [String] {
        try move(
            classed
                .filter { $0.unitClass.isQuarantined && packagePath(of: $0.unit.mainFile) != nil }
                .map(\.unit.name)
        )
    }

    /// Moves the units of `snapshot` that the quarantine takes, as
    /// `quarantine(_:)` does for classed units: a snapshot unit's main file
    /// is under the root when its path is a path in the package.
    func quarantine(_ snapshot: IndexSnapshot) throws -> [String] {
        try move(
            snapshot.units
                .filter { $0.unitClass.isQuarantined && $0.path.isEmpty == false && $0.path.hasPrefix("/") == false }
                .map(\.name)
        )
    }

    /// Moves the units named `names` from the store's `v5/units` into the
    /// quarantine folder, emptied first, and returns the names, sorted.
    private func move(_ names: [String]) throws -> [String] {
        let manager = FileManager.default
        let scratchURL = URL(fileURLWithPath: scratch)
        let units = scratchURL
            .appendingPathComponent(BuildSession.storeDirectory)
            .appendingPathComponent(BuildSession.unitsPath)
        let destination = scratchURL.appendingPathComponent(Self.quarantineDirectory)
        let moved = names.sorted()
        do {
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in moved {
                try manager.moveItem(
                    at: units.appendingPathComponent(name),
                    to: destination.appendingPathComponent(name)
                )
            }
        } catch {
            throw QuarantineFailure(
                description: "units couldn't be moved out of the store: \(error.localizedDescription)"
            )
        }
        return moved
    }

    /// The class `unit` gets from its own header (`system`, `otherPackage`,
    /// `otherModule` or `stale`), or nil when it is a candidate for
    /// `duplicate`, `variant` or `kept`.
    private func headerClass(of unit: IndexUnitFact) -> UnitClass? {
        if unit.isSystem {
            return .system
        }
        let mainFile = unit.mainFile.precomposedStringWithCanonicalMapping
        guard
            mainFile.isEmpty == false,
            let path = packagePath(of: mainFile),
            mainFile != scratch,
            mainFile.hasPrefix(scratch + "/") == false,
            let first = path.split(separator: "/").first,
            Self.buildFolders.contains(String(first)) == false,
            isInDependency(mainFile) == false
        else {
            return .otherPackage
        }
        guard let target = modules[unit.module] else {
            return .otherModule
        }
        guard FileManager.default.fileExists(atPath: mainFile), sources[target]?.contains(path) == true else {
            return .stale
        }
        return nil
    }
}
