//
//  CountingIndexSource.swift
//  SwiftStatsCoreTests
//
//  An `IndexStoreSource` around another that counts how often each unit
//  and record is asked for, and fails for the names it is told to, for the
//  index walk's tests (M7, design §2.2).
//

@testable import SwiftStatsCore

/// Counts the reads of a wrapped index source.
final class CountingIndexSource: IndexStoreSource {
    /// What the source was told to fail.
    struct Refused: Error, CustomStringConvertible {
        /// The unit or record name refused.
        let name: String

        /// The refusal, for a failure reason.
        var description: String {
            "refused \(name)"
        }
    }

    /// The source read through.
    private let base: any IndexStoreSource
    /// The unit and record names whose reads fail.
    private let failing: Set<String>
    /// How often each unit was read, by name.
    private(set) var unitReads: [String: Int] = [:]
    /// How often each record was read, by name.
    private(set) var recordReads: [String: Int] = [:]

    /// A source reading through `base`, failing reads of units and records
    /// named in `failing`.
    init(_ base: any IndexStoreSource, failing: Set<String>) {
        self.base = base
        self.failing = failing
    }

    /// The base's unit names.
    func unitNames() throws -> [String] {
        try base.unitNames()
    }

    /// The base's unit `name`, counted; `Refused` when it is to fail.
    func unit(named name: String) throws -> IndexUnitFact {
        unitReads[name, default: 0] += 1
        guard failing.contains(name) == false else {
            throw Refused(name: name)
        }
        return try base.unit(named: name)
    }

    /// The base's record `name`, counted; `Refused` when it is to fail.
    func record(named name: String) throws -> IndexRecordFact {
        recordReads[name, default: 0] += 1
        guard failing.contains(name) == false else {
            throw Refused(name: name)
        }
        return try base.record(named: name)
    }

    deinit {
        // Nothing to release beyond stored properties.
    }
}
