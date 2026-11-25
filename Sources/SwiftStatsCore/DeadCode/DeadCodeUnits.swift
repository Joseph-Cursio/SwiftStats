//
//  DeadCodeUnits.swift
//  SwiftStatsCore
//
//  An outskirts run's covered units and its dead lines (M7, design §5.4).
//  A unit is maximal when no other unit holds it: a record below a covered
//  record by `parentKey`; a nested type, or one of the type's own
//  extension records, under a covered type; anything whose main region
//  lies in a region of another unit (a type's body or one of its
//  extensions, an extension, a record). When two units hold each other,
//  the one first by identifier counts. Dead lines are the sum of the
//  maximal units' lines per module, so they don't depend on the order of
//  the entries, and a local function outskirts lists inside an unused
//  function counts once.
//

/// A run's covered units.
struct DeadCodeUnits {
    /// Each record's parent record, by key.
    private let parents: [String: String]
    /// The units, by identifier.
    private var units: [String: DeadCodeUnit] = [:]

    /// No units yet, records' parents read from `parents` (each record's
    /// `parentKey`, by key).
    init(parents: [String: String]) {
        self.parents = parents
    }

    /// Adds `unit`, unless a unit of its identifier is there.
    mutating func add(_ unit: DeadCodeUnit) {
        if units[unit.identifier] == nil {
            units[unit.identifier] = unit
        }
    }

    /// The units no other unit holds, by identifier.
    func maximal() -> [DeadCodeUnit] {
        let ordered = units.values.sorted { CodePointOrder.precedes($0.identifier, $1.identifier) }
        return ordered.filter { unit in
            ordered.contains { other in
                guard other.identifier != unit.identifier, holds(other, unit) else {
                    return false
                }
                let mutual = holds(unit, other) && CodePointOrder.precedes(unit.identifier, other.identifier)
                return mutual == false
            } == false
        }
    }

    /// The maximal units' lines per module; a module with none is absent.
    func lines() -> [String: Int] {
        var lines: [String: Int] = [:]
        for part in maximal().flatMap(\.parts) where part.lines > 0 {
            lines[part.module, default: 0] += part.lines
        }
        return lines
    }

    /// Whether `outer` holds `inner`.
    private func holds(_ outer: DeadCodeUnit, _ inner: DeadCodeUnit) -> Bool {
        guard let main = inner.regions.first else {
            return false
        }
        if case .record(let outerKey) = outer.kind, case .record(let innerKey) = inner.kind {
            return ancestors(of: innerKey).contains(outerKey)
        }
        if case .type(let outerIdentity) = outer.kind {
            if case .type(let innerIdentity) = inner.kind, innerIdentity.isNested(in: outerIdentity) {
                return true
            }
            if inner.kind == .extensionRecord, outer.extensions.contains(main) {
                return true
            }
        }
        return outer.regions.contains { region in
            region != main && region.file == main.file && region.span.contains(main.span)
        }
    }

    /// The keys of the records above the record `key`, by `parentKey`.
    private func ancestors(of key: String) -> Set<String> {
        var found: Set<String> = []
        var current = parents[key]
        while let parent = current, found.insert(parent).inserted {
            current = parents[parent]
        }
        return found
    }
}
