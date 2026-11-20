//
//  FamilyIndex.swift
//  SwiftStatsCore
//
//  A snapshot's function families, found by any member's key, so a clone
//  copy's records can be read as the families they belong to.
//

/// A snapshot's families by their members' keys.
struct FamilyIndex {
    /// The families, in `FunctionFamily.families`' order.
    let families: [FunctionFamily]
    /// The position in `families` of each record's family, by record key.
    private let familyByKey: [String: Int]

    /// The families of `rows`.
    init(_ rows: [FunctionRow]) {
        families = FunctionFamily.families(rows)
        var positions: [String: Int] = [:]
        for (index, family) in families.enumerated() {
            for member in family.members where positions[member.key] == nil {
                positions[member.key] = index
            }
        }
        familyByKey = positions
    }

    /// The units of `instance`, in source order: the families whose root
    /// it covers whole (for a computed property, all its accessors); when
    /// there are none, the family of the record holding it, as a fragment
    /// of the copy's own lines; none when no record holds it either.
    func units(of instance: CloneInstance) -> [CloneUnit] {
        let covered = Set(instance.wholes)
        var seen: Set<Int> = []
        var units: [CloneUnit] = []
        for key in instance.wholes {
            guard let index = familyByKey[key], seen.insert(index).inserted else {
                continue
            }
            let family = families[index]
            if let root = family.root {
                if covered.contains(root.key) {
                    units.append(CloneUnit(
                        family: family,
                        lines: root.strippedLines,
                        start: root.startLine,
                        end: root.endLine,
                        whole: true
                    ))
                }
            } else if family.accessors.allSatisfy({ covered.contains($0.key) }) {
                units.append(CloneUnit(
                    family: family,
                    lines: family.strippedLines,
                    start: family.accessors.map(\.startLine).min() ?? family.startLine,
                    end: family.accessors.map(\.endLine).max() ?? family.startLine,
                    whole: true
                ))
            }
        }
        guard units.isEmpty, let holder = instance.containing, let index = familyByKey[holder] else {
            return units
        }
        return [
            CloneUnit(
                family: families[index],
                lines: instance.strippedLines,
                start: instance.range.start.line,
                end: instance.range.end.line,
                whole: false
            )
        ]
    }
}
