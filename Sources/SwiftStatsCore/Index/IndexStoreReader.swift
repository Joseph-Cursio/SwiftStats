//
//  IndexStoreReader.swift
//  SwiftStatsCore
//
//  The product's `IndexStoreSource` (M7, design §2.1–§2.2): a thin reader
//  over indexstore-db's `IndexStore` product, pinned by revision in
//  `Package.swift`, and the only file that imports it (the `IndexStore`
//  and `IndexStoreDB` modules share type names; only this one is linked,
//  and nothing outside this file names either). It loads the build
//  toolchain's libIndexStore.dylib once, through `BlockingAsync` (the
//  library's one `async` call), opens the store (the directory holding
//  `v5`) and copies every value out into SwiftStats' own facts inside the
//  closure that yields it, since `IndexStore`'s values are non-escapable.
//  It never filters: classing units is `UnitFilter`'s job.
//
//  Values are made as the checker's `index-check.py dump` makes them, so
//  the two readers can be compared fact for fact (check u0):
//  - unit names, and a unit's record names (duplicates kept), sorted in
//    code point order, as Python's `sorted()` sorts them, not by
//    `String`'s `<`, which compares NFC forms; a unit's dependencies of
//    kind `unit` as read, duplicates kept;
//  - main files and record files as real paths in NFC: realpath(3), and
//    for a file that no longer exists (a stale unit's) the real path of
//    its longest existing ancestor with the rest appended; "" for a unit
//    with no main file;
//  - a record's file is the first in code point order of the paths the
//    non-system units read so far name it with, units outside the package
//    included (the reader doesn't know the root; the dump notes paths from
//    the same units, though it lists only the records of units under the
//    root), so a record shared with an outside unit, one of a file with
//    the same name and contents, may get the outside path;
//  - a unit's modification date is its unit file's, read with stat(2) to
//    the nanosecond: the `IndexStore` API gives it only as a `Date`, whose
//    `Double` can't hold nanoseconds, and libIndexStore takes it from the
//    unit file's status too.
//

import Foundation
import IndexStore

/// Reads an index store through indexstore-db's `IndexStore`.
final class IndexStoreReader: IndexStoreSource {
    /// Why a store couldn't be opened, or a unit's date read.
    struct Failure: Error, CustomStringConvertible {
        /// What failed and why, for the `index` collector's reason.
        let description: String
    }

    /// The indexstore-db revision `Package.swift` pins, the tag
    /// `swift-6.4.2-RELEASE`; a test keeps it equal to the revision in
    /// `Package.resolved`.
    static let pinned = "64aa0b26913249c4e7c21d351a215fba02702003"
    /// The pinned revision's tag: the Swift release it ships with.
    static let tag = "swift-6.4.2-RELEASE"

    /// The `index` collector's build identity: the pinned commit, as the
    /// effect collector's is SwiftEffectInference's.
    static var identity: String {
        "git:" + pinned
    }

    /// The `index` collector's version: the reader and its tag.
    static var version: String {
        "indexstore-db " + tag
    }

    /// The open store.
    private let store: IndexStore
    /// The store's unit files, `<store>/v5/units`.
    private let unitFiles: URL
    /// The paths the non-system units read so far give each record, as
    /// stored.
    private var recordPaths: [String: Set<String>] = [:]
    /// Whether every unit's records have been noted, so a record no unit
    /// named has no file.
    private var notedEveryUnit = false

    /// A reader over `store`, whose directory is `directory`.
    private init(store: IndexStore, directory: URL) {
        self.store = store
        unitFiles = directory.appendingPathComponent(BuildSession.unitsPath)
    }

    /// A reader over the store at `store` (the directory holding `v5`),
    /// with the libIndexStore.dylib at `library`.
    static func open(store: URL, library: URL) throws -> any IndexStoreSource {
        let loaded: IndexStoreLibrary
        do {
            loaded = try BlockingAsync.run { try await IndexStoreLibrary.at(dylibPath: library) }
        } catch {
            throw Failure(description: "libIndexStore.dylib didn't load: \(error)")
        }
        do {
            return Self(store: try loaded.indexStore(at: store), directory: store)
        } catch {
            throw Failure(description: "the index store at \(store.path) doesn't read: \(error)")
        }
    }

    /// `path` as a real path in NFC: realpath(3) of it, or of its longest
    /// existing ancestor with the missing rest appended; a relative path,
    /// or one with no existing ancestor, only normalized.
    static func realPath(_ path: String) -> String {
        guard path.hasPrefix("/") else {
            return path.precomposedStringWithCanonicalMapping
        }
        var head = path
        while head.count > 1, head.hasSuffix("/") {
            head.removeLast()
        }
        var missing: [Substring] = []
        while true {
            if let resolved = realpath(head, nil) {
                defer { free(resolved) }
                let real = String(cString: resolved)
                let joined = missing.isEmpty ? real : ([real == "/" ? "" : Substring(real)] + missing)
                    .joined(separator: "/")
                return joined.precomposedStringWithCanonicalMapping
            }
            guard head != "/", let slash = head.lastIndex(of: "/") else {
                return path.precomposedStringWithCanonicalMapping
            }
            missing.insert(head[head.index(after: slash)...], at: 0)
            head = slash == head.startIndex ? "/" : String(head[..<slash])
        }
    }

    /// Every unit's name, in code point order.
    func unitNames() -> [String] {
        var names: [String] = []
        store.unitNames(sorted: false).forEach { name in
            names.append(name.string)
            return .continue
        }
        return Self.codePointSorted(names)
    }

    /// The unit named `name`: its header, its records' names and its
    /// dependencies of kind `unit`; its records' paths are noted unless it
    /// is a system unit.
    func unit(named name: String) throws -> IndexUnitFact {
        let unit = try store.unit(named: name)
        let isSystem = unit.isSystemUnit
        var records: [String] = []
        var modules: [IndexUnitFact.ModuleDependency] = []
        unit.dependencies.forEach { dependency in
            switch dependency.kind {
            case .record:
                let record = dependency.name.string
                records.append(record)
                if isSystem == false {
                    recordPaths[record, default: []].insert(dependency.filePath.string)
                }

            case .unit:
                modules.append(IndexUnitFact.ModuleDependency(
                    module: dependency.moduleName.string,
                    isSystem: dependency.isSystem
                ))

            default:
                break
            }
            return .continue
        }
        return IndexUnitFact(
            name: name,
            module: unit.moduleName.string,
            mainFile: unit.hasMainFile ? Self.realPath(unit.mainFile.string) : "",
            target: unit.target.string,
            isSystem: isSystem,
            modified: try modification(ofUnit: name),
            records: Self.codePointSorted(records),
            moduleDependencies: modules
        )
    }

    /// The record named `name`, with every occurrence it holds, as read.
    func record(named name: String) throws -> IndexRecordFact {
        let record = try store.record(named: name)
        var occurrences: [IndexOccurrenceFact] = []
        record.occurrences.forEach { occurrence in
            var relations: [IndexOccurrenceFact.Relation] = []
            occurrence.relations.forEach { relation in
                let related = relation.symbol
                relations.append(IndexOccurrenceFact.Relation(
                    roles: relation.roles.rawValue,
                    usr: related.usr.string,
                    name: related.name.string,
                    kind: Int(related.kind.rawValue),
                    subkind: Int(related.subKind.rawValue),
                    properties: related.properties.rawValue
                ))
                return .continue
            }
            let symbol = occurrence.symbol
            let position = occurrence.position
            occurrences.append(IndexOccurrenceFact(
                line: position.line,
                column: position.column,
                roles: occurrence.roles.rawValue,
                usr: symbol.usr.string,
                name: symbol.name.string,
                kind: Int(symbol.kind.rawValue),
                subkind: Int(symbol.subKind.rawValue),
                properties: symbol.properties.rawValue,
                relations: relations
            ))
            return .continue
        }
        return IndexRecordFact(name: name, file: try file(ofRecord: name), occurrences: occurrences)
    }

    /// The real path the non-system units give the record `name`, the
    /// first in code point order; every unit is read first when none read
    /// so far names it, and "" when none does.
    private func file(ofRecord name: String) throws -> String {
        if recordPaths[name] == nil, notedEveryUnit == false {
            for unit in unitNames() {
                _ = try self.unit(named: unit)
            }
            notedEveryUnit = true
        }
        let paths = (recordPaths[name] ?? []).map { $0.isEmpty ? "" : Self.realPath($0) }
        return paths.min(by: Self.codePointPrecedes) ?? ""
    }

    /// The unit file `name`'s modification date, to the nanosecond.
    private func modification(ofUnit name: String) throws -> IndexUnitFact.ModificationDate {
        var status = stat()
        let path = unitFiles.appendingPathComponent(name).path
        guard stat(path, &status) == 0 else {
            let reason = String(cString: strerror(errno))
            throw Failure(description: "unit \(name)'s file has no modification date: \(reason)")
        }
        return IndexUnitFact.ModificationDate(
            seconds: Int64(status.st_mtimespec.tv_sec),
            nanoseconds: Int64(status.st_mtimespec.tv_nsec)
        )
    }

    deinit {
        // Nothing to release: the store closes itself when it goes.
    }
}
