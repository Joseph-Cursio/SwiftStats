//
//  RecordedIndexSource.swift
//  SwiftStatsCore
//
//  An `IndexStoreSource` over recorded reader output (M7, design §2.2 and
//  §13): the JSON `Scripts/index-check.py dump` writes with its own ctypes
//  reader, so recordings don't come from the code they test. A recording
//  names paths by placeholders (`@ROOT@`, `@BUILD@`, …); the source puts
//  back the paths it is given where a unit's main file or a record's file
//  starts with one. A dump holds the records of units under the package
//  root only, so asking for another unit's record fails, as would asking
//  for a unit or record the recording lacks. Unit tests use it; nothing in
//  the product does.
//

import Foundation

/// Reads recorded reader output.
struct RecordedIndexSource: IndexStoreSource {
    /// A unit or record the recording doesn't hold.
    enum Missing: Error, CustomStringConvertible {
        /// No unit of this name.
        case unit(String)
        /// No record of this name.
        case record(String)

        /// What is missing, for a failure reason.
        var description: String {
            switch self {
            case let .unit(name):
                "the recording holds no unit \(name)"
            case let .record(name):
                "the recording holds no record \(name)"
            }
        }
    }

    /// The parts of a dump the source reads.
    private struct Recording: Decodable {
        /// Its units.
        let units: [IndexUnitFact]
        /// Its records.
        let records: [IndexRecordFact]
    }

    /// The units, by name.
    let units: [String: IndexUnitFact]
    /// The records, by name.
    let records: [String: IndexRecordFact]

    /// A source holding `units` and `records`; of two with one name, the
    /// later is kept.
    init(units: [IndexUnitFact], records: [IndexRecordFact]) {
        self.units = Dictionary(units.map { ($0.name, $0) }) { _, later in later }
        self.records = Dictionary(records.map { ($0.name, $0) }) { _, later in later }
    }

    /// A source holding the dump in `recording`, with each placeholder in
    /// `paths` (such as `@ROOT@`) replaced by its path where a main file
    /// or record file starts with it.
    init(recording: Data, restoring paths: [String: String]) throws {
        let decoded = try JSONDecoder().decode(Recording.self, from: recording)
        let restore = { (path: String) in Self.restore(path, paths: paths) }
        self.init(
            units: decoded.units.map { unit in
                IndexUnitFact(
                    name: unit.name,
                    module: unit.module,
                    mainFile: restore(unit.mainFile),
                    target: unit.target,
                    isSystem: unit.isSystem,
                    modified: unit.modified,
                    records: unit.records,
                    moduleDependencies: unit.moduleDependencies
                )
            },
            records: decoded.records.map { record in
                IndexRecordFact(name: record.name, file: restore(record.file), occurrences: record.occurrences)
            }
        )
    }

    /// `path` with a leading placeholder of `paths` replaced by its path:
    /// the placeholder must be the whole path or be followed by `/`.
    private static func restore(_ path: String, paths: [String: String]) -> String {
        for (placeholder, replacement) in paths {
            if path == placeholder {
                return replacement
            }
            if path.hasPrefix(placeholder + "/") {
                return replacement + path.dropFirst(placeholder.count)
            }
        }
        return path
    }

    /// Every unit's name, sorted.
    func unitNames() -> [String] {
        units.keys.sorted()
    }

    /// The unit named `name`, or `Missing.unit`.
    func unit(named name: String) throws -> IndexUnitFact {
        guard let unit = units[name] else {
            throw Missing.unit(name)
        }
        return unit
    }

    /// The record named `name`, or `Missing.record`.
    func record(named name: String) throws -> IndexRecordFact {
        guard let record = records[name] else {
            throw Missing.record(name)
        }
        return record
    }
}
