//
//  CopyUnit.swift
//  SwiftStatsCore
//
//  One unit of a clone copy in an earlier snapshot, matched to the family
//  now holding it, and whether it changed since (PRD §8, divergent
//  clones): a non-sweep commit since then changed the family, and a hunk
//  of the diff since then lies in the unit's lines.
//

/// A unit of an earlier copy, with its family now.
struct CopyUnit {
    /// The unit in the earlier snapshot.
    let unit: CloneUnit
    /// The family now holding it.
    let family: FunctionFamily
    /// The non-sweep commits since the earlier snapshot that changed that family.
    let commits: [HistoryLogEntry]
    /// Whether it changed since the earlier snapshot.
    let changed: Bool

    /// The family now, as history names it.
    var ref: FamilyRef {
        FamilyRef(family)
    }

    /// The unit as an item lists it: the family now, its commits since the
    /// earlier snapshot, and when the latest was made.
    var copy: SignalItem.CloneCopy {
        SignalItem.CloneCopy(
            family: family.id,
            file: family.file,
            line: family.startLine,
            changes: commits.count,
            lastChange: commits.map(\.date).max()
        )
    }
}
